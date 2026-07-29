import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/send_result.dart';

enum ConnectionStatus { success, authFailed, connectionRefused }

/// Manages a single TCP connection to a ClipLink daemon.
class SocketService {
  final String host;
  final int port;
  final String pin;

  Socket? _socket;
  bool _authenticated = false;
  bool _disposed = false;
  String? _remoteName;
  Set<String> _capabilities = const {};

  /// Buffer for incomplete lines arriving over TCP.
  String _lineBuffer = '';

  String? get remoteName => _remoteName;
  bool get supportsUpload => _capabilities.contains('upload-v1');
  final _responseController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get responses => _responseController.stream;

  final _connectionController = StreamController<bool>.broadcast();
  Stream<bool> get connectionState => _connectionController.stream;

  /// Emits the current line buffer size (bytes received for in-flight message).
  final _progressController = StreamController<int>.broadcast();
  Stream<int> get receiveProgress => _progressController.stream;

  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const _maxReconnectDelay = 30;

  bool get isConnected => _socket != null && _authenticated;

  SocketService({required this.host, required this.port, required this.pin});

  Future<ConnectionStatus> connect() async {
    try {
      _socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );

      final authMsg = jsonEncode({
        'type': 'auth',
        'pin': pin,
        'device_name': 'Flick',
      });
      _socket!.write('$authMsg\n');
      await _socket!.flush();

      final completer = Completer<ConnectionStatus>();
      StreamSubscription? sub;

      sub = _socket!.listen(
        (data) {
          _lineBuffer += utf8.decode(data);
          _progressController.add(_lineBuffer.length);
          // Process all complete lines (ending with \n).
          // The remainder (after last \n) stays in _lineBuffer.
          while (true) {
            final newlineIdx = _lineBuffer.indexOf('\n');
            if (newlineIdx == -1) break;
            final line = _lineBuffer.substring(0, newlineIdx).trim();
            _lineBuffer = _lineBuffer.substring(newlineIdx + 1);
            if (line.isEmpty) continue;
            try {
              final json = jsonDecode(line) as Map<String, dynamic>;
              if (json['type'] == 'auth_ok') {
                _authenticated = true;
                _remoteName = json['name'] as String?;
                final capabilities = json['capabilities'];
                _capabilities = capabilities is List
                    ? capabilities.whereType<String>().toSet()
                    : const {};
                _reconnectAttempts = 0;
                _startHeartbeat();
                if (!completer.isCompleted) {
                  completer.complete(ConnectionStatus.success);
                }
              } else if (json['type'] == 'auth_fail') {
                if (!completer.isCompleted) {
                  completer.complete(ConnectionStatus.authFailed);
                }
              } else if (_authenticated) {
                _responseController.add(json);
              }
            } catch (_) {}
          }
        },
        onDone: () {
          _handleDisconnect();
          if (!completer.isCompleted) {
            completer.complete(ConnectionStatus.connectionRefused);
          }
        },
        onError: (e) {
          _handleDisconnect();
          if (!completer.isCompleted) {
            completer.complete(ConnectionStatus.connectionRefused);
          }
        },
        cancelOnError: false,
      );

      final result = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          sub?.cancel();
          _socket?.destroy();
          return ConnectionStatus.connectionRefused;
        },
      );
      return result;
    } catch (_) {
      _handleDisconnect();
      return ConnectionStatus.connectionRefused;
    }
  }

  Future<SendResult?> send(String text, String id) async {
    if (_socket == null || !_authenticated) return null;
    try {
      final msg = jsonEncode({'type': 'send', 'payload': text, 'id': id});
      _socket!.write('$msg\n');
      await _socket!.flush();
      return null;
    } catch (_) {
      return SendResult(status: SendStatus.error, id: id, message: '发送失败');
    }
  }

  /// Send a key press to the daemon.
  Future<SendResult?> sendKey(String key, String id) async {
    if (_socket == null || !_authenticated) return null;
    try {
      final msg = jsonEncode({'type': 'key', 'key': key, 'id': id});
      _socket!.write('$msg\n');
      await _socket!.flush();
      return null;
    } catch (_) {
      return SendResult(status: SendStatus.error, id: id, message: '发送失败');
    }
  }

  /// Query the daemon's clipboard for content type and size.
  Future<void> queryClipboard() async {
    if (_socket == null || !_authenticated) return;
    try {
      final msg = jsonEncode({'type': 'clipboard_query'});
      _socket!.write('$msg\n');
      await _socket!.flush();
    } catch (_) {}
  }

  /// Fetch clipboard content from the daemon.
  Future<void> fetchClipboard(
    String contentType, {
    int fileIndex = 0,
    String id = '',
  }) async {
    if (_socket == null || !_authenticated) return;
    try {
      final msg = jsonEncode({
        'type': 'clipboard_fetch',
        'content_type': contentType,
        if (contentType == 'file') 'index': fileIndex,
        'id': id,
      });
      _socket!.write('$msg\n');
      await _socket!.flush();
    } catch (_) {}
  }

  Future<bool> startUpload({
    required String id,
    required String kind,
    required String filename,
    required int sizeBytes,
  }) {
    return _sendJson({
      'type': 'upload_begin',
      'id': id,
      'kind': kind,
      'filename': filename,
      'size_bytes': sizeBytes,
    });
  }

  Future<bool> sendUploadChunk({
    required String id,
    required int sequence,
    required String payloadBase64,
  }) {
    return _sendJson({
      'type': 'upload_chunk',
      'id': id,
      'seq': sequence,
      'payload_base64': payloadBase64,
    });
  }

  Future<bool> finishUpload({
    required String id,
    required int sizeBytes,
    required String sha256,
  }) {
    return _sendJson({
      'type': 'upload_finish',
      'id': id,
      'size_bytes': sizeBytes,
      'sha256': sha256,
    });
  }

  Future<void> cancelUpload(String id) async {
    await _sendJson({'type': 'upload_cancel', 'id': id});
  }

  Future<bool> _sendJson(Map<String, dynamic> message) async {
    if (_socket == null || !_authenticated) return false;
    try {
      _socket!.write('${jsonEncode(message)}\n');
      await _socket!.flush();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_socket != null && _authenticated) {
        try {
          _socket!.write('{"type":"ping"}\n');
          _socket!.flush();
        } catch (_) {
          _handleDisconnect();
        }
      }
    });
  }

  void _handleDisconnect() {
    _authenticated = false;
    _capabilities = const {};
    _lineBuffer = '';
    _socket?.destroy();
    _socket = null;
    _heartbeatTimer?.cancel();
    _connectionController.add(false);
    if (!_disposed) _startReconnect();
  }

  void _startReconnect() {
    _reconnectTimer?.cancel();
    final delay = (_reconnectAttempts < 5)
        ? (1 << _reconnectAttempts)
        : _maxReconnectDelay;
    _reconnectAttempts++;
    _reconnectTimer = Timer(Duration(seconds: delay), () async {
      if (_disposed) return;
      final ok = await connect();
      if (ok != ConnectionStatus.success && !_disposed) _startReconnect();
    });
  }

  void disconnect() {
    _disposed = true;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _socket?.destroy();
    _socket = null;
    _authenticated = false;
    _capabilities = const {};
    _lineBuffer = '';
    _connectionController.add(false);
  }

  void dispose() {
    disconnect();
    _responseController.close();
    _connectionController.close();
    _progressController.close();
  }
}
