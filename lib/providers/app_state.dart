import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../models/discovered_device.dart';
import '../models/paired_device.dart';
import '../models/send_result.dart';
import '../models/upload_state.dart';
import '../services/discovery_service.dart';
import '../services/socket_service.dart';
import '../services/storage_service.dart';
import '../services/file_saver.dart';

enum ConnectResult { success, wrongPin, connectionFailed }

/// Clipboard fetch status.
enum ClipboardFetchStatus { idle, querying, fetching, done, error }

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}

/// Central application state, managed via Provider.
class AppState extends ChangeNotifier {
  // ── Discovery ──────────────────────────────────────────────────────────
  final DiscoveryService _discovery = DiscoveryService();
  final List<DiscoveredDevice> _discoveredDevices = [];
  bool _scanning = false;
  Timer? _scanTimeout;

  List<DiscoveredDevice> get discoveredDevices =>
      List.unmodifiable(_discoveredDevices);
  bool get isScanning => _scanning;

  // ── Paired devices ─────────────────────────────────────────────────────
  List<PairedDevice> _pairedDevices = [];
  List<PairedDevice> get pairedDevices => List.unmodifiable(_pairedDevices);

  // ── Connection ─────────────────────────────────────────────────────────
  SocketService? _socket;
  bool _connected = false;
  String _connectedDeviceName = '';
  bool _authenticating = false;
  String? _authError;
  DiscoveredDevice? _needsPinFor;

  // Stored for reconnection
  String _lastIp = '';
  int _lastPort = 9527;
  String _lastPin = '';

  bool get isConnected => _connected;
  String get connectedDeviceName => _connectedDeviceName;
  bool get isAuthenticating => _authenticating;
  String? get authError => _authError;
  DiscoveredDevice? get needsPinFor => _needsPinFor;

  // ── Send ───────────────────────────────────────────────────────────────
  SendStatus _sendStatus = SendStatus.idle;
  String _sendMessage = '';

  SendStatus get sendStatus => _sendStatus;
  String get sendMessage => _sendMessage;

  // ── Clipboard Pull ─────────────────────────────────────────────────────
  ClipboardFetchStatus _clipboardStatus = ClipboardFetchStatus.idle;
  String _clipboardMessage = '';
  Map<String, dynamic>? _clipboardInfo;

  /// Progress of current clipboard fetch (0.0 to 1.0), or -1 if not fetching.
  double _clipboardProgress = -1;

  ClipboardFetchStatus get clipboardStatus => _clipboardStatus;
  String get clipboardMessage => _clipboardMessage;
  Map<String, dynamic>? get clipboardInfo => _clipboardInfo;
  double get clipboardProgress => _clipboardProgress;

  /// Max auto-fetch size for text (512KB).
  static const int _maxAutoFetchSize = 524288;

  // ── Mobile → Desktop attachments ───────────────────────────────────────
  UploadState _upload = const UploadState();
  File? _uploadFile;
  RandomAccessFile? _uploadReader;
  _DigestSink? _uploadDigestResult;
  ByteConversionSink? _uploadDigest;
  Timer? _uploadTimer;
  int _uploadChunkSize = 0;
  int _uploadSequence = 0;

  UploadState get upload => _upload;
  bool get supportsUpload => _connected && (_socket?.supportsUpload ?? false);

  final _uuid = const Uuid();

  // ── Operation timeout / reconnect ──────────────────────────────────────
  StreamSubscription<int>? _progressSub;
  Timer? _opTimer;
  VoidCallback? _pendingRetry;
  static const _opTimeoutShort = Duration(seconds: 3);
  static const _opTimeoutLong = Duration(seconds: 15);

  bool _reconnecting = false;

  // ─── Init ──────────────────────────────────────────────────────────────

  StreamSubscription? _responseSub;
  StreamSubscription<bool>? _connectionSub;

  AppState() {
    _loadPaired();
  }

  Future<void> _loadPaired() async {
    _pairedDevices = await StorageService.loadPairedDevices();
    notifyListeners();
  }

  // ─── Discovery ─────────────────────────────────────────────────────────
  Future<void> startScan() async {
    _discoveredDevices.clear();
    _scanning = true;
    notifyListeners();

    _scanTimeout?.cancel();
    _scanTimeout = Timer(const Duration(seconds: 15), () {
      if (_scanning) stopScan();
    });

    _discovery.devices.listen((device) {
      final idx = _discoveredDevices.indexWhere((d) => d.key == device.key);
      if (idx >= 0) {
        _discoveredDevices[idx] = device;
      } else {
        _discoveredDevices.add(device);
      }
      notifyListeners();
    });

    try {
      await _discovery.startScan();
    } catch (_) {}
  }

  void stopScan() {
    _discovery.stopScan();
    _scanning = false;
    _scanTimeout?.cancel();
    _scanTimeout = null;
    notifyListeners();
  }

  Future<ConnectResult> connectWithPin(
    DiscoveredDevice device,
    String pin,
  ) async {
    return _connect(device.ip, device.port, device.name, pin, isPaired: false);
  }

  Future<ConnectResult> connectPaired(PairedDevice device) async {
    return _connect(
      device.ip,
      device.port,
      device.name,
      device.pin,
      isPaired: true,
      pairedKey: device.key,
    );
  }

  Future<ConnectResult> _connect(
    String ip,
    int port,
    String name,
    String pin, {
    bool isPaired = false,
    String? pairedKey,
  }) async {
    _authenticating = true;
    _authError = null;
    _reconnecting = false;
    notifyListeners();

    _socket?.dispose();
    _socket = SocketService(host: ip, port: port, pin: pin);

    final status = await _socket!.connect();
    _authenticating = false;

    switch (status) {
      case ConnectionStatus.success:
        _connected = true;
        _lastIp = ip;
        _lastPort = port;
        _lastPin = pin;
        final daemonName = _socket?.remoteName ?? name;
        _connectedDeviceName = daemonName;
        _authError = null;
        if (!_reconnecting) {
          await StorageService.savePairedDevice(
            PairedDevice(ip: ip, port: port, name: daemonName, pin: pin),
          );
          await _loadPaired();
        }
        _responseSub?.cancel();
        _responseSub = _socket!.responses.listen(_onResponse);
        _connectionSub?.cancel();
        _connectionSub = _socket!.connectionState.listen(_onConnectionChange);

        // If this was a reconnect, retry the pending operation
        if (_reconnecting && _pendingRetry != null) {
          _reconnecting = false;
          final retry = _pendingRetry!;
          _pendingRetry = null;
          notifyListeners(); // clear stale error messages
          retry();
        } else if (_reconnecting) {
          _reconnecting = false;
          _pendingRetry = null;
          _sendStatus = SendStatus.idle;
          _sendMessage = '';
          _clipboardStatus = ClipboardFetchStatus.idle;
          _clipboardMessage = '';
        }
        return ConnectResult.success;

      case ConnectionStatus.authFailed:
        _connected = false;
        _socket?.dispose();
        _socket = null;
        _reconnecting = false;
        _pendingRetry = null;
        _opTimer?.cancel();
        if (isPaired && pairedKey != null) {
          await StorageService.removePairedDevice(pairedKey);
          await _loadPaired();
          _authError = null;
          _needsPinFor = DiscoveredDevice(ip: ip, port: port, name: name);
        } else {
          _authError = 'PIN 码错误';
        }
        notifyListeners();
        return ConnectResult.wrongPin;

      case ConnectionStatus.connectionRefused:
        _connected = false;
        _socket?.dispose();
        _socket = null;
        if (!_reconnecting) {
          _authError = '无法连接，请检查服务端是否已启动';
        }
        _reconnecting = false;
        _pendingRetry = null;
        _opTimer?.cancel();
        if (_upload.blocksOtherActions) {
          _setUploadError('连接已断开');
        }
        _sendStatus = SendStatus.error;
        _sendMessage = '连接已断开';
        _clipboardStatus = ClipboardFetchStatus.error;
        _clipboardMessage = '连接已断开';
        notifyListeners();
        return ConnectResult.connectionFailed;
    }
  }

  void disconnect() {
    _clearUploadTimer();
    _closeUploadReader();
    _uploadFile = null;
    _upload = const UploadState();
    _opTimer?.cancel();
    _pendingRetry = null;
    _reconnecting = false;
    _socket?.disconnect();
    _socket = null;
    _connected = false;
    _connectedDeviceName = '';
    _lastIp = '';
    _lastPort = 9527;
    _lastPin = '';
    _sendStatus = SendStatus.idle;
    _sendMessage = '';
    _clipboardStatus = ClipboardFetchStatus.idle;
    _clipboardMessage = '';
    _clipboardInfo = null;
    _responseSub?.cancel();
    _connectionSub?.cancel();
    notifyListeners();
  }

  DiscoveredDevice? consumeNeedsPinFor() {
    final d = _needsPinFor;
    _needsPinFor = null;
    return d;
  }

  Future<void> unpair(PairedDevice device) async {
    await StorageService.removePairedDevice(device.key);
    await _loadPaired();
    notifyListeners();
  }

  // ─── Operation timeout helper ──────────────────────────────────────────

  /// Start a timeout that triggers reconnection and retry on expiry.
  void _startOpTimer(Duration timeout, VoidCallback retry) {
    _opTimer?.cancel();
    _pendingRetry = retry;
    _opTimer = Timer(timeout, () {
      if (!_connected || _socket == null) return;
      _reconnectAndRetry();
    });
  }

  void _clearOpTimer() {
    _opTimer?.cancel();
    _opTimer = null;
    _pendingRetry = null;
  }

  void _onConnectionChange(bool connected) {
    if (!connected && !_reconnecting) {
      if (_upload.blocksOtherActions) {
        _setUploadError('连接已断开');
      }
      // Heartbeat detected a dead connection — try silent reconnect.
      _reconnectAndRetry();
    }
  }

  /// Start tracking download progress for clipboard fetch.
  void _startProgressTracking(String contentType) {
    _stopProgressTracking();
    final info = _clipboardInfo;
    if (info == null || _socket == null) return;
    // Extract size: text/image have top-level size_bytes; files have nested files[].size
    int sizeBytes = (info['size_bytes'] as num?)?.toInt() ?? 0;
    if (sizeBytes <= 0 && contentType == 'file') {
      final files = info['files'] as List<dynamic>?;
      if (files != null && files.isNotEmpty) {
        sizeBytes = (files[0]['size'] as num?)?.toInt() ?? 0;
      }
    }
    if (sizeBytes <= 0) return;

    // Estimated total transmitted size (accounts for base64 + JSON overhead)
    final totalEstimate = (contentType == 'text')
        ? sizeBytes.toDouble()
        : sizeBytes * 1.4;

    _clipboardProgress = 0;
    _progressSub = _socket!.receiveProgress.listen((received) {
      _clipboardProgress = (received / totalEstimate).clamp(0.0, 1.0);
      notifyListeners();
    });
  }

  void _stopProgressTracking() {
    _progressSub?.cancel();
    _progressSub = null;
    _clipboardProgress = -1;
  }

  Future<void> _reconnectAndRetry() async {
    if (_reconnecting) return;
    if (_lastIp.isEmpty || _lastPin.isEmpty) return;
    _reconnecting = true;
    _socket?.disconnect();
    _socket = null;
    _connected = false;
    _responseSub?.cancel();
    notifyListeners();

    await _connect(_lastIp, _lastPort, _connectedDeviceName, _lastPin);
  }

  // ─── Send ──────────────────────────────────────────────────────────────

  Future<void> send(String text) async {
    if (!_connected || _socket == null || _upload.blocksOtherActions) return;
    if (text.trim().isEmpty) {
      _sendStatus = SendStatus.error;
      _sendMessage = '不能发送空文本';
      notifyListeners();
      return;
    }

    _sendStatus = SendStatus.sending;
    _sendMessage = '发送中...';
    notifyListeners();

    // Start timeout — if no ack/nack within 3s, reconnect and retry
    final id = _uuid.v4();
    _startOpTimer(_opTimeoutShort, () => send(text));

    final result = await _socket!.send(text, id);
    if (result != null) {
      _clearOpTimer();
      _sendStatus = result.status;
      _sendMessage = result.message;
      notifyListeners();
    }
  }

  Future<void> sendEnter() async {
    if (!_connected || _socket == null || _upload.blocksOtherActions) return;

    _sendStatus = SendStatus.sending;
    _sendMessage = '发送回车中...';
    notifyListeners();

    _startOpTimer(_opTimeoutShort, () => sendEnter());

    final id = _uuid.v4();
    final result = await _socket!.sendKey('enter', id);
    if (result != null) {
      _clearOpTimer();
      _sendStatus = result.status;
      _sendMessage = result.message;
      notifyListeners();
    }
  }

  Future<void> selectImage() async {
    if (!supportsUpload || _upload.blocksOtherActions) return;
    _upload = const UploadState(
      status: UploadStatus.selecting,
      message: '正在选择图片...',
    );
    notifyListeners();

    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
      if (image == null) {
        _upload = const UploadState();
        notifyListeners();
        return;
      }
      await _prepareUpload(File(image.path), UploadKind.image);
    } catch (_) {
      _setUploadError('无法读取所选图片');
    }
  }

  Future<void> selectFile() async {
    if (!supportsUpload || _upload.blocksOtherActions) return;
    _upload = const UploadState(
      status: UploadStatus.selecting,
      message: '正在选择文件...',
    );
    notifyListeners();

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: false,
      );
      final path = result == null || result.files.length != 1
          ? null
          : result.files.single.path;
      if (path == null) {
        _upload = const UploadState();
        notifyListeners();
        return;
      }
      await _prepareUpload(File(path), UploadKind.file);
    } catch (_) {
      _setUploadError('无法读取所选文件');
    }
  }

  Future<void> _prepareUpload(File file, UploadKind kind) async {
    try {
      final size = await file.length();
      if (size == 0) {
        _setUploadError('不能发送空文件');
        return;
      }
      _uploadFile = file;
      _upload = UploadState(
        status: UploadStatus.ready,
        kind: kind,
        filename: file.uri.pathSegments.last,
        totalBytes: size,
        message: '准备发送',
      );
      notifyListeners();
    } catch (_) {
      _setUploadError('无法读取所选文件');
    }
  }

  Future<void> startUpload() async {
    final socket = _socket;
    final file = _uploadFile;
    final kind = _upload.kind;
    if (!supportsUpload ||
        socket == null ||
        file == null ||
        kind == null ||
        !_upload.isReady) {
      return;
    }

    try {
      _uploadReader = await file.open();
      _uploadDigestResult = _DigestSink();
      _uploadDigest = sha256.startChunkedConversion(_uploadDigestResult!);
      _uploadChunkSize = 0;
      _uploadSequence = 0;
      final id = _uuid.v4();
      _upload = _upload.copyWith(
        status: UploadStatus.uploading,
        id: id,
        receivedBytes: 0,
        message: '正在连接电脑...',
      );
      notifyListeners();

      final sent = await socket.startUpload(
        id: id,
        kind: kind.name,
        filename: _upload.filename,
        sizeBytes: _upload.totalBytes,
      );
      if (!sent) {
        _setUploadError('上传请求发送失败');
        return;
      }
      _resetUploadTimer();
    } catch (_) {
      _setUploadError('无法读取所选文件');
    }
  }

  Future<void> cancelUpload() async {
    final id = _upload.id;
    _clearUploadTimer();
    await _closeUploadReader();
    _uploadFile = null;
    _upload = UploadState(
      status: UploadStatus.cancelled,
      id: id,
      message: '已取消发送',
    );
    notifyListeners();
    if (id.isNotEmpty) {
      await _socket?.cancelUpload(id);
    }
  }

  void _resetUploadTimer() {
    _uploadTimer?.cancel();
    _uploadTimer = Timer(_opTimeoutLong, () {
      _setUploadError('上传连接超时');
    });
  }

  void _clearUploadTimer() {
    _uploadTimer?.cancel();
    _uploadTimer = null;
  }

  Future<void> _closeUploadReader() async {
    final reader = _uploadReader;
    _uploadReader = null;
    _uploadDigest = null;
    _uploadDigestResult = null;
    if (reader != null) {
      await reader.close();
    }
  }

  void _setUploadError(String message) {
    _clearUploadTimer();
    _closeUploadReader();
    _uploadFile = null;
    _upload = UploadState(status: UploadStatus.error, message: message);
    notifyListeners();
  }

  Future<void> _sendNextUploadChunk() async {
    final socket = _socket;
    final reader = _uploadReader;
    if (socket == null ||
        reader == null ||
        _upload.status != UploadStatus.uploading) {
      _setUploadError('上传连接已断开');
      return;
    }

    try {
      final chunk = await reader.read(_uploadChunkSize);
      if (_upload.status != UploadStatus.uploading) return;
      if (chunk.isEmpty) {
        _uploadDigest?.close();
        final digest = _uploadDigestResult?.value.toString();
        if (digest == null) {
          _setUploadError('无法校验文件完整性');
          return;
        }
        final sent = await socket.finishUpload(
          id: _upload.id,
          sizeBytes: _upload.totalBytes,
          sha256: digest,
        );
        if (!sent) {
          _setUploadError('上传完成请求发送失败');
          return;
        }
        _resetUploadTimer();
        return;
      }

      _uploadDigest?.add(chunk);
      final sent = await socket.sendUploadChunk(
        id: _upload.id,
        sequence: _uploadSequence,
        payloadBase64: base64Encode(chunk),
      );
      if (!sent) {
        _setUploadError('上传数据发送失败');
        return;
      }
      _uploadSequence += 1;
      _resetUploadTimer();
    } catch (_) {
      _setUploadError('读取文件失败');
    }
  }

  void _onUploadReady(Map<String, dynamic> json) {
    if (json['id'] != _upload.id || _upload.status != UploadStatus.uploading) {
      return;
    }
    final chunkSize = (json['chunk_size'] as num?)?.toInt() ?? 0;
    if (chunkSize <= 0 || chunkSize > 64 * 1024) {
      _setUploadError('电脑返回了无效的上传参数');
      return;
    }
    _uploadChunkSize = chunkSize;
    _upload = _upload.copyWith(message: '正在发送...');
    notifyListeners();
    _sendNextUploadChunk();
  }

  void _onUploadChunkAck(Map<String, dynamic> json) {
    if (json['id'] != _upload.id || _upload.status != UploadStatus.uploading) {
      return;
    }
    final sequence = (json['seq'] as num?)?.toInt();
    if (sequence != _uploadSequence - 1) {
      _setUploadError('电脑返回了错误的上传确认');
      return;
    }
    final received = (json['received_bytes'] as num?)?.toInt() ?? 0;
    if (received < _upload.receivedBytes || received > _upload.totalBytes) {
      _setUploadError('电脑返回了无效的上传进度');
      return;
    }
    _upload = _upload.copyWith(receivedBytes: received, message: '正在发送...');
    notifyListeners();
    _sendNextUploadChunk();
  }

  void _onUploadCompleted() {
    final kind = _upload.kind;
    _clearUploadTimer();
    _closeUploadReader();
    _uploadFile = null;
    _upload = UploadState(
      status: UploadStatus.sent,
      kind: kind,
      message: kind == UploadKind.image ? '图片已写入电脑剪贴板' : '文件已写入电脑剪贴板',
    );
    notifyListeners();
  }

  void queryClipboard() {
    if (_upload.blocksOtherActions) return;
    _stopProgressTracking();
    _clipboardStatus = ClipboardFetchStatus.idle;
    if (!_connected || _socket == null) return;
    _clipboardStatus = ClipboardFetchStatus.querying;
    _clipboardMessage = '正在查询剪贴板...';
    _clipboardInfo = null;
    notifyListeners();

    _startOpTimer(_opTimeoutShort, queryClipboard);
    _socket!.queryClipboard();
  }

  void confirmClipboardFetch() {
    if (_upload.blocksOtherActions) return;
    if (_clipboardInfo == null) return;
    final contentType = _clipboardInfo!['content_type'] as String? ?? '';
    if (contentType.isEmpty || contentType == 'none') return;

    _clipboardStatus = ClipboardFetchStatus.fetching;
    _clipboardMessage = '正在获取...';
    notifyListeners();
    final duration = (contentType == 'text') ? _opTimeoutShort : _opTimeoutLong;
    _startOpTimer(duration, confirmClipboardFetch);
    _startProgressTracking(contentType);
    _socket?.fetchClipboard(contentType, id: _uuid.v4());
  }

  void cancelClipboardFetch() {
    _clearOpTimer();
    _clipboardStatus = ClipboardFetchStatus.idle;
    _clipboardMessage = '';
    _clipboardInfo = null;
    notifyListeners();
  }

  // ─── Response handler ──────────────────────────────────────────────────

  void _onResponse(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? '';
    final id = json['id'] as String? ?? '';

    if (type == 'upload_ready') {
      _onUploadReady(json);
      return;
    }
    if (type == 'upload_chunk_ack') {
      _onUploadChunkAck(json);
      return;
    }
    if (id.isNotEmpty && id == _upload.id) {
      if (_upload.status == UploadStatus.uploading) {
        if (type == 'ack') {
          _onUploadCompleted();
        } else if (type == 'nack') {
          _setUploadError(json['message'] as String? ?? '上传失败');
        }
      }
      return;
    }
    if (type == 'clipboard_info') {
      _onClipboardInfo(json);
      return;
    }
    if (type == 'clipboard_data') {
      _onClipboardData(json);
      return;
    }

    // Send/key ack/nack — cancel timeout on any response.
    _clearOpTimer();
    final status = json['status'] as String? ?? '';

    if (type == 'ack') {
      final result = SendResult.fromAck(id, status);
      _sendStatus = result.status;
      _sendMessage = result.message;
    } else if (type == 'nack') {
      final message = json['message'] as String? ?? '';
      final result = SendResult.fromNack(id, status, message);
      _sendStatus = result.status;
      _sendMessage = result.message;
    }

    notifyListeners();
  }

  void _onClipboardInfo(Map<String, dynamic> json) {
    _clearOpTimer();
    _stopProgressTracking();
    final contentType = json['content_type'] as String? ?? 'none';

    if (contentType == 'none') {
      _clipboardStatus = ClipboardFetchStatus.done;
      _clipboardMessage = '电脑剪贴板为空';
      _clipboardInfo = null;
      notifyListeners();
      return;
    }

    _clipboardInfo = json;

    if (contentType == 'text') {
      final sizeBytes = (json['size_bytes'] as num?)?.toInt() ?? 0;
      if (sizeBytes <= _maxAutoFetchSize) {
        _clipboardStatus = ClipboardFetchStatus.fetching;
        _clipboardMessage = '正在获取文本...';
        notifyListeners();
        _startOpTimer(_opTimeoutShort, () {
          if (_clipboardInfo != null) confirmClipboardFetch();
        });
        _socket?.fetchClipboard('text', id: _uuid.v4());
        return;
      }
    }

    _clipboardStatus = ClipboardFetchStatus.done;
    _clipboardMessage = '';
    notifyListeners();
  }

  Future<void> _onClipboardData(Map<String, dynamic> json) async {
    _clearOpTimer();
    _stopProgressTracking();
    final contentType = json['content_type'] as String? ?? 'error';

    if (contentType == 'error') {
      _clipboardStatus = ClipboardFetchStatus.error;
      _clipboardMessage = json['message'] as String? ?? '获取失败';
      _clipboardInfo = null;
      notifyListeners();
      return;
    }

    try {
      switch (contentType) {
        case 'text':
          await _handleClipboardText(json);
        case 'image':
          await _handleClipboardImage(json);
        case 'file':
          await _handleClipboardFile(json);
        default:
          _clipboardStatus = ClipboardFetchStatus.error;
          _clipboardMessage = '未知内容类型: $contentType';
      }
    } catch (e) {
      _clipboardStatus = ClipboardFetchStatus.error;
      _clipboardMessage = '处理失败: $e';
    }
    _clipboardInfo = null;
    notifyListeners();
  }

  Future<void> _handleClipboardText(Map<String, dynamic> json) async {
    final payload = json['payload'] as String? ?? '';
    if (payload.isEmpty) {
      _clipboardStatus = ClipboardFetchStatus.error;
      _clipboardMessage = '剪贴板文本为空';
      return;
    }
    await Clipboard.setData(ClipboardData(text: payload));
    _clipboardStatus = ClipboardFetchStatus.done;
    _clipboardMessage = '文本已复制到剪贴板';
  }

  Future<void> _handleClipboardImage(Map<String, dynamic> json) async {
    final b64 = json['payload_base64'] as String? ?? '';
    if (b64.isEmpty) {
      _clipboardStatus = ClipboardFetchStatus.error;
      _clipboardMessage = '图片数据为空';
      return;
    }

    final pngBytes = base64Decode(b64);

    try {
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/cliplink_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(pngBytes);
      await Gal.putImage(file.path);
      _clipboardStatus = ClipboardFetchStatus.done;
      _clipboardMessage = '图片已保存到相册';
    } catch (e) {
      _clipboardStatus = ClipboardFetchStatus.error;
      _clipboardMessage = '图片保存失败: $e';
    }
  }

  Future<void> _handleClipboardFile(Map<String, dynamic> json) async {
    final b64 = json['payload_base64'] as String? ?? '';
    final filename = json['filename'] as String? ?? 'file';
    if (b64.isEmpty) {
      _clipboardStatus = ClipboardFetchStatus.error;
      _clipboardMessage = '文件数据为空';
      return;
    }

    final fileBytes = base64Decode(b64);

    try {
      final ok = await FileSaver.saveToDownloads(filename, fileBytes);
      if (ok) {
        _clipboardStatus = ClipboardFetchStatus.done;
        _clipboardMessage = '文件已保存到下载目录';
      } else {
        _clipboardStatus = ClipboardFetchStatus.error;
        _clipboardMessage = '文件保存失败';
      }
    } catch (e) {
      _clipboardStatus = ClipboardFetchStatus.error;
      _clipboardMessage = '文件保存失败: $e';
    }
  }

  // ─── Cleanup ───────────────────────────────────────────────────────────

  @override
  void dispose() {
    _opTimer?.cancel();
    _clearUploadTimer();
    _closeUploadReader();
    _progressSub?.cancel();
    _discovery.dispose();
    _socket?.dispose();
    _responseSub?.cancel();
    _connectionSub?.cancel();
    super.dispose();
  }
}
