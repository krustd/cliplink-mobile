import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import '../models/discovered_device.dart';
import '../models/paired_device.dart';
import '../models/send_result.dart';
import '../services/discovery_service.dart';
import '../services/socket_service.dart';
import '../services/storage_service.dart';
import '../services/file_saver.dart';

enum ConnectResult { success, wrongPin, connectionFailed }

/// Clipboard fetch status.
enum ClipboardFetchStatus { idle, querying, fetching, done, error }

/// Central application state, managed via Provider.
class AppState extends ChangeNotifier {
  // ── Discovery ──────────────────────────────────────────────────────────
  final DiscoveryService _discovery = DiscoveryService();
  final List<DiscoveredDevice> _discoveredDevices = [];
  bool _scanning = false;
  Timer? _scanTimeout;

  List<DiscoveredDevice> get discoveredDevices => List.unmodifiable(_discoveredDevices);
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

  ClipboardFetchStatus get clipboardStatus => _clipboardStatus;
  String get clipboardMessage => _clipboardMessage;
  Map<String, dynamic>? get clipboardInfo => _clipboardInfo;

  /// Max auto-fetch size for text (512KB).
  static const int _maxAutoFetchSize = 524288;

  final _uuid = const Uuid();
  StreamSubscription? _responseSub;

  // ── Operation timeout / reconnect ──────────────────────────────────────
  Timer? _opTimer;
  VoidCallback? _pendingRetry;
  static const _opTimeoutShort = Duration(seconds: 3);
  static const _opTimeoutLong = Duration(seconds: 15);

  bool _reconnecting = false;

  // ─── Init ──────────────────────────────────────────────────────────────

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

  Future<ConnectResult> connectWithPin(DiscoveredDevice device, String pin) async {
    return _connect(device.ip, device.port, device.name, pin, isPaired: false);
  }

  Future<ConnectResult> connectPaired(PairedDevice device) async {
    return _connect(device.ip, device.port, device.name, device.pin, isPaired: true, pairedKey: device.key);
  }

  Future<ConnectResult> _connect(
      String ip, int port, String name, String pin,
      {bool isPaired = false, String? pairedKey}) async {
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
          await StorageService.savePairedDevice(PairedDevice(
            ip: ip, port: port, name: daemonName, pin: pin,
          ));
          await _loadPaired();
        }
        _responseSub?.cancel();
        _responseSub = _socket!.responses.listen(_onResponse);
        notifyListeners();

        // If this was a reconnect, retry the pending operation
        if (_reconnecting && _pendingRetry != null) {
          _reconnecting = false;
          final retry = _pendingRetry!;
          _pendingRetry = null;
          retry();
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
        _sendStatus = SendStatus.error;
        _sendMessage = '连接已断开';
        _clipboardStatus = ClipboardFetchStatus.error;
        _clipboardMessage = '连接已断开';
        notifyListeners();
        return ConnectResult.connectionFailed;
    }
  }

  void disconnect() {
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
    if (!_connected || _socket == null) return;
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
    if (!_connected || _socket == null) return;

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

  // ─── Clipboard Pull ────────────────────────────────────────────────────

  void queryClipboard() {
    if (!_connected || _socket == null) return;
    _clipboardStatus = ClipboardFetchStatus.querying;
    _clipboardMessage = '正在查询剪贴板...';
    _clipboardInfo = null;
    notifyListeners();

    _startOpTimer(_opTimeoutShort, queryClipboard);
    _socket!.queryClipboard();
  }

  void confirmClipboardFetch() {
    if (_clipboardInfo == null) return;
    final contentType = _clipboardInfo!['content_type'] as String? ?? '';
    if (contentType.isEmpty || contentType == 'none') return;

    _clipboardStatus = ClipboardFetchStatus.fetching;
    _clipboardMessage = '正在获取...';
    notifyListeners();

    // Use longer timeout for image/file fetches which may be large
    final timeout = (contentType == 'text') ? _opTimeoutShort : _opTimeoutLong;
    _startOpTimer(timeout, confirmClipboardFetch);
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

    if (type == 'clipboard_info') {
      _onClipboardInfo(json);
      return;
    }
    if (type == 'clipboard_data') {
      _onClipboardData(json);
      return;
    }

    // Send/key ack/nack — cancel timeout on any response
    _clearOpTimer();

    final id = json['id'] as String? ?? '';
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
      final file = File('${dir.path}/cliplink_${DateTime.now().millisecondsSinceEpoch}.png');
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
    _scanTimeout?.cancel();
    _discovery.dispose();
    _socket?.dispose();
    _responseSub?.cancel();
    super.dispose();
  }
}
