import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/discovered_device.dart';
import '../models/paired_device.dart';
import '../models/send_result.dart';
import '../services/discovery_service.dart';
import '../services/socket_service.dart';
import '../services/storage_service.dart';

/// Central application state, managed via Provider.
class AppState extends ChangeNotifier {
  // ── Discovery ──────────────────────────────────────────────────────────
  final DiscoveryService _discovery = DiscoveryService();
  final List<DiscoveredDevice> _discoveredDevices = [];
  bool _scanning = false;

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

  bool get isConnected => _connected;
  String get connectedDeviceName => _connectedDeviceName;
  bool get isAuthenticating => _authenticating;
  String? get authError => _authError;

  // ── Send ───────────────────────────────────────────────────────────────
  SendStatus _sendStatus = SendStatus.idle;
  String _sendMessage = '';

  SendStatus get sendStatus => _sendStatus;
  String get sendMessage => _sendMessage;

  final _uuid = const Uuid();
  StreamSubscription? _responseSub;

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
    } catch (_) {
      // Scan start may fail; discovery may still work on retry
    }
  }

  void stopScan() {
    _discovery.stopScan();
    _scanning = false;
    notifyListeners();
  }

  // ─── Connection ────────────────────────────────────────────────────────

  /// Connect to a discovered device with a PIN.
  Future<bool> connectWithPin(DiscoveredDevice device, String pin) async {
    return _connect(device.ip, device.port, device.name, pin);
  }

  /// Connect to a paired device using its stored PIN.
  Future<bool> connectPaired(PairedDevice device) async {
    return _connect(device.ip, device.port, device.name, device.pin);
  }

  Future<bool> _connect(
      String ip, int port, String name, String pin) async {
    _authenticating = true;
    _authError = null;
    notifyListeners();

    _socket?.dispose();
    _socket = SocketService(host: ip, port: port, pin: pin);

    final ok = await _socket!.connect();
    _authenticating = false;

    if (ok) {
      _connected = true;
      _connectedDeviceName = name;
      _authError = null;

      // Save pairing
      await StorageService.savePairedDevice(PairedDevice(
        ip: ip,
        port: port,
        name: name,
        pin: pin,
      ));
      _loadPaired();

      // Listen for send responses
      _responseSub?.cancel();
      _responseSub = _socket!.responses.listen(_onResponse);
    } else {
      _connected = false;
      _authError = '认证失败，请检查 PIN 码';
      _socket?.dispose();
      _socket = null;
    }

    notifyListeners();
    return ok;
  }

  /// Disconnect from current device.
  void disconnect() {
    _socket?.disconnect();
    _socket = null;
    _connected = false;
    _connectedDeviceName = '';
    _sendStatus = SendStatus.idle;
    _sendMessage = '';
    _responseSub?.cancel();
    notifyListeners();
  }

  // ─── Send ──────────────────────────────────────────────────────────────

  /// Send text to the connected daemon.
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

    final id = _uuid.v4();
    final result = await _socket!.send(text, id);
    if (result != null) {
      // Immediate error (not connected, etc.)
      _sendStatus = result.status;
      _sendMessage = result.message;
      notifyListeners();
    }
    // Otherwise, wait for response via _onResponse
  }

  void _onResponse(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? '';
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

  // ─── Cleanup ───────────────────────────────────────────────────────────

  @override
  void dispose() {
    _discovery.dispose();
    _socket?.dispose();
    _responseSub?.cancel();
    super.dispose();
  }
}
