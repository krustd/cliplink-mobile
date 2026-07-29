import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/discovered_device.dart';
import '../models/paired_device.dart';
import '../providers/app_state.dart';
import 'pin_screen.dart';
import 'send_screen.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '9527');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().startScan();
    });
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _onConnected() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const SendScreen()),
    );
  }

  void _showPin(DiscoveredDevice device) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PinScreen(device: device, onConnected: _onConnected),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Flick',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          Consumer<AppState>(
            builder: (_, state, _) => IconButton(
              icon: state.isScanning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              tooltip: state.isScanning ? '扫描中...' : '刷新',
              onPressed: () {
                if (state.isScanning) {
                  state.stopScan();
                } else {
                  state.startScan();
                }
              },
            ),
          ),
        ],
      ),
      body: Consumer<AppState>(
        builder: (context, state, _) {
          if (state.isAuthenticating) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在连接...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              // Error banner
              if (state.authError != null) _ErrorBanner(state.authError!),

              // Paired devices
              if (state.pairedDevices.isNotEmpty) ...[
                _SectionHeader(
                  icon: Icons.link_rounded,
                  title: '已配对',
                  color: Colors.green,
                ),
                const SizedBox(height: 8),
                ...state.pairedDevices.map(
                  (d) => _PairedCard(
                    device: d,
                    isOnline: state.discoveredDevices.any((dd) => dd.key == d.key),
                    onTap: () async {
                      final result = await state.connectPaired(d);
                      if (!mounted) return;
                      if (result == ConnectResult.success) {
                        _onConnected();
                      } else {
                        final device = state.consumeNeedsPinFor();
                        if (device != null) _showPin(device);
                      }
                    },
                  ),
                ),
              const SizedBox(height: 24),
              ],

              // Discovered devices
              _SectionHeader(
                icon: Icons.wifi_find_rounded,
                title: '发现的设备',
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 8),
              if (state.discoveredDevices.isEmpty)
                _EmptyState(isScanning: state.isScanning)
              else
                ...state.discoveredDevices
                    .where(
                        (d) => !state.pairedDevices.any((p) => p.key == d.key))
                    .map((d) => _DeviceCard(
                          device: d,
                          onTap: () => _showPin(d),
                        )),

              const SizedBox(height: 28),

              // Manual entry
              _SectionHeader(
                icon: Icons.edit_rounded,
                title: '手动连接',
                color: Colors.orange,
              ),
              const SizedBox(height: 10),
              _ManualEntry(
                ipController: _ipController,
                portController: _portController,
                onConnect: () {
                  final ip = _ipController.text.trim();
                  final port =
                      int.tryParse(_portController.text.trim()) ?? 9527;
                  if (ip.isNotEmpty) {
                    _showPin(DiscoveredDevice(
                      ip: ip,
                      port: port,
                      name: '$ip:$port',
                    ));
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PairedCard extends StatelessWidget {
  final PairedDevice device;
  final VoidCallback onTap;
  final bool isOnline;
  const _PairedCard({required this.device, required this.onTap, required this.isOnline});

  @override
  Widget build(BuildContext context) {
    final color = isOnline ? Colors.green : Colors.grey;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: color.shade50,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${device.ip}:${device.port}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: Colors.grey.shade400,
                  tooltip: '取消配对',
                  onPressed: () {
                    context.read<AppState>().unpair(device);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final DiscoveredDevice device;
  final VoidCallback onTap;
  const _DeviceCard({required this.device, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.desktop_windows_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${device.ip}:${device.port}',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.add_circle_outline_rounded,
                    color: Theme.of(context).colorScheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isScanning;
  const _EmptyState({required this.isScanning});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(
            Icons.wifi_off_rounded,
            size: 48,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 12),
          Text(
            isScanning ? '正在扫描...' : '未发现设备',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '确保电脑已启动 cliplinkd\n且在同一局域网',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner(this.message);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.red.shade100),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade600, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualEntry extends StatelessWidget {
  final TextEditingController ipController;
  final TextEditingController portController;
  final VoidCallback onConnect;

  const _ManualEntry({
    required this.ipController,
    required this.portController,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: ipController,
                    decoration: const InputDecoration(
                      labelText: 'IP 地址',
                      hintText: '192.168.1.100',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: portController,
                    decoration: const InputDecoration(
                      labelText: '端口',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onConnect,
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text('连接'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
