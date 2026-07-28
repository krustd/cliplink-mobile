import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/discovered_device.dart';

/// Multicast-based device discovery with TCP subnet scan fallback.
///
/// ## Discovery layers (tried in order):
/// 1. **Multicast** (224.0.0.167:discoveryPort) — primary, burst of 3
/// 2. **TCP subnet scan** — automatic fallback after 5s with no results
class DiscoveryService {
  static const _multicastAddr = '224.0.0.167';
  final int discoveryPort;

  RawDatagramSocket? _socket;
  StreamSubscription? _subscription;
  Timer? _broadcastTimer;
  Timer? _burstTimer1;
  Timer? _burstTimer2;
  Timer? _subnetScanTimer;
  bool _running = false;
  bool _subnetScanActive = false;

  final StreamController<DiscoveredDevice> _deviceController =
      StreamController<DiscoveredDevice>.broadcast();

  Stream<DiscoveredDevice> get devices => _deviceController.stream;
  bool get isScanning => _running;

  DiscoveryService({this.discoveryPort = 9528});

  /// Start scanning. Sends a multicast burst, then periodic refreshes.
  /// If no devices found after 5 seconds, triggers TCP subnet scan.
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

    // Multicast burst: 3 rapid sends
    _sendBurst();

    // Re-send every 5 seconds
    _broadcastTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_running) _sendMulticast();
    });

    // Subnet scan fallback after 5s
    _subnetScanTimer = Timer(const Duration(seconds: 5), () {
      if (_running) _startSubnetScan();
    });
  }

  /// 3-packet burst with backoff: t=0, +100ms, +600ms
  void _sendBurst() {
    _sendMulticast();
    _burstTimer1 = Timer(const Duration(milliseconds: 100), () {
      if (_running) _sendMulticast();
    });
    _burstTimer2 = Timer(const Duration(milliseconds: 600), () {
      if (_running) _sendMulticast();
    });
  }

  void _sendMulticast() {
    if (_socket == null) return;
    try {
      final data = utf8.encode(jsonEncode({'type': 'discover'}));
      _socket!.send(data, InternetAddress(_multicastAddr), discoveryPort);
    } catch (_) {}
  }

  // ─── TCP Subnet Scan ──────────────────────────────────────────────────

  void _startSubnetScan() {
    if (_subnetScanActive) return;
    _subnetScanActive = true;

    _scanLocalSubnets().then((devices) {
      for (final d in devices) {
        _deviceController.add(d);
      }
    });
  }

  Future<List<DiscoveredDevice>> _scanLocalSubnets() async {
    final devices = <DiscoveredDevice>[];
    try {
      final interfaces = await NetworkInterface.list();
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type != InternetAddressType.IPv4 || addr.isLoopback) {
            continue;
          }
          final subnet = _subnetBase(addr);
          if (subnet == null) continue;

          final ips = List.generate(254, (i) => '$subnet.${i + 1}');
          for (var batch in _chunk(ips, 10)) {
            final results = await Future.wait(
              batch.map((ip) => _probeDevice(ip)),
            );
            for (final r in results) {
              if (r != null) devices.add(r);
            }
          }
        }
      }
    } catch (_) {}
    return devices;
  }

  Future<DiscoveredDevice?> _probeDevice(String ip) async {
    try {
      final socket = await Socket.connect(
        ip,
        9527,
        timeout: const Duration(milliseconds: 800),
      );
      socket.write(
        '{"type":"auth","pin":"","device_name":"ClipLink Scanner"}\n',
      );
      await socket.flush();

      final completer = Completer<DiscoveredDevice?>();
      socket.listen(
        (data) {
          final text = utf8.decode(data);
          for (final line in text.split('\n')) {
            if (line.trim().isEmpty) continue;
            try {
              final json = jsonDecode(line.trim());
              if (json['type'] == 'auth_ok' || json['type'] == 'auth_fail') {
                completer.complete(DiscoveredDevice(
                  ip: ip,
                  port: 9527,
                  name: '设备 ($ip)',
                ));
                return;
              }
            } catch (_) {}
          }
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(null);
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete(null);
        },
        cancelOnError: true,
      );

      final result = await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          socket.destroy();
          return null;
        },
      );
      socket.destroy();
      return result;
    } catch (_) {
      return null;
    }
  }

  String? _subnetBase(InternetAddress addr) {
    final raw = addr.rawAddress;
    if (raw.length != 4) return null;
    return '${raw[0]}.${raw[1]}.${raw[2]}';
  }

  Iterable<List<T>> _chunk<T>(List<T> list, int size) sync* {
    for (var i = 0; i < list.length; i += size) {
      yield list.sublist(
          i, i + size > list.length ? list.length : i + size);
    }
  }

  // ─── Lifecycle ───────────────────────────────────────────────────────

  void stopScan() {
    _running = false;
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _burstTimer1?.cancel();
    _burstTimer1 = null;
    _burstTimer2?.cancel();
    _burstTimer2 = null;
    _subnetScanTimer?.cancel();
    _subnetScanTimer = null;
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
