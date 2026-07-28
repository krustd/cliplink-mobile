import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/discovered_device.dart';

/// UDP broadcast-based device discovery.
///
/// ## Platform support
///
/// | Platform    | Status  | Notes |
/// |-------------|---------|-------|
/// | Android     | Full    | Requires `INTERNET` permission in AndroidManifest.xml |
/// | iOS         | Full    | Requests local network access on first use |
/// | OpenHarmony | Full*   | Uses `dart:io` RawDatagramSocket; requires `ohos.permission.INTERNET` in module.json5. Some ROMs may restrict UDP broadcast — fallback to manual IP entry. |
///
/// The discovery protocol sends a single UDP datagram to `255.255.255.255:<port>`
/// every 3 seconds while scanning. ClipLink daemons on the LAN respond directly
/// with their TCP address.
class DiscoveryService {
  final int discoveryPort;
  RawDatagramSocket? _socket;
  StreamSubscription? _subscription;
  Timer? _broadcastTimer;
  bool _running = false;

  final StreamController<DiscoveredDevice> _deviceController =
      StreamController<DiscoveredDevice>.broadcast();

  Stream<DiscoveredDevice> get devices => _deviceController.stream;

  bool get isScanning => _running;

  DiscoveryService({this.discoveryPort = 9528});

  /// Start scanning the LAN for ClipLink daemons. Errors are silently handled
  /// (scanning is best-effort on networks without broadcast support).
  Future<void> startScan() async {
    if (_running) return;
    _running = true;

    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    } catch (_) {
      _running = false;
      return;
    }

    _subscription = _socket!.listen(
      (event) {
        if (event != RawSocketEvent.read) return;
        final datagram = _socket?.receive();
        if (datagram == null) return;

        try {
          final data = utf8.decode(datagram.data);
          final json = jsonDecode(data) as Map<String, dynamic>;
          if (json['type'] == 'announce') {
            final device = DiscoveredDevice(
              ip: datagram.address.address,
              port: (json['tcp_port'] as num?)?.toInt() ?? 9527,
              name: json['name'] as String? ?? 'Unknown',
            );
            _deviceController.add(device);
          }
        } catch (_) {}
      },
      onError: (_) {},
      cancelOnError: false,
    );

    // Send initial broadcast
    _tryBroadcast();

    // Re-broadcast every 3 seconds
    _broadcastTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_running) _tryBroadcast();
    });
  }

  void _tryBroadcast() {
    if (_socket == null) return;
    try {
      final data = utf8.encode(jsonEncode({'type': 'discover'}));
      _socket!.send(data, InternetAddress('255.255.255.255'), discoveryPort);
    } catch (_) {}
  }

  /// Stop scanning and release resources.
  void stopScan() {
    _running = false;
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _socket?.close();
    _socket = null;
  }

  void dispose() {
    stopScan();
    _deviceController.close();
  }
}
