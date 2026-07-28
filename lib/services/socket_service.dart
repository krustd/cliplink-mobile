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

  final _responseController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get responses => _responseController.stream;

  final _connectionController = StreamController<bool>.broadcast();
  Stream<bool> get connectionState => _connectionController.stream;

  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const _maxReconnectDelay = 30;

  bool get isConnected => _socket != null && _authenticated;

  SocketService({required this.host, required this.port, required this.pin});

  Future<ConnectionStatus> connect() async {
    try {
      _socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 5));

      final authMsg = jsonEncode({
        'type': 'auth',
        'pin': pin,
        'device_name': 'ClipLink Mobile',
      });
      _socket!.write('$authMsg\n');
      await _socket!.flush();

      final completer = Completer<ConnectionStatus>();
      StreamSubscription? sub;

      sub = _socket!.listen(
        (data) {
          final text = utf8.decode(data);
          for (final line in text.split('\n')) {
            if (line.trim().isEmpty) continue;
            try {
              final json = jsonDecode(line.trim()) as Map<String, dynamic>;
              if (json['type'] == 'auth_ok') {
                _authenticated = true;
                _connectionController.add(true);
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

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
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
    _connectionController.add(false);
  }

  void dispose() {
    disconnect();
    _responseController.close();
    _connectionController.close();
  }
}
