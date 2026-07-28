import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/discovered_device.dart';
import '../models/paired_device.dart';
import '../providers/app_state.dart';
import 'pin_screen.dart';
import 'send_screen.dart';

/// Device discovery and selection screen.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final _manualIpController = TextEditingController();
  final _manualPortController = TextEditingController(text: '9527');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().startScan();
    });
  }

  @override
  void dispose() {
    _manualIpController.dispose();
    _manualPortController.dispose();
    super.dispose();
  }

  void _navigateToSend() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const SendScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ClipLink - 选择设备'),
        actions: [
          Consumer<AppState>(
            builder: (_, state, _) => IconButton(
              icon: Icon(state.isScanning ? Icons.stop : Icons.refresh),
              tooltip: state.isScanning ? '停止扫描' : '重新扫描',
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
                  Text('正在连接...'),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Scanning indicator
              if (state.isScanning)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('正在扫描局域网...'),
                    ],
                  ),
                ),

              // Error display
              if (state.authError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            state.authError!,
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Paired devices
              if (state.pairedDevices.isNotEmpty) ...[
                const _SectionHeader(title: '已配对设备', icon: Icons.devices),
                ...state.pairedDevices.map((d) => _PairedDeviceTile(
                      device: d,
                      onTap: () async {
                        final ok = await state.connectPaired(d);
                        if (ok && mounted) _navigateToSend();
                      },
                    )),
                const SizedBox(height: 16),
              ],

              // Discovered devices
              const _SectionHeader(title: '发现的设备', icon: Icons.search),
              if (state.discoveredDevices.isEmpty && !state.isScanning)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      '未发现设备\n请确保电脑端已启动且在同一局域网',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              ...state.discoveredDevices
                  .where((d) => !state.pairedDevices.any((p) => p.key == d.key))
                  .map((d) => _DiscoveredDeviceTile(
                        device: d,
                        onTap: () => _showPinDialog(d),
                      )),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),

              // Manual entry
              const _SectionHeader(title: '手动连接', icon: Icons.edit),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _manualIpController,
                      decoration: const InputDecoration(
                        labelText: 'IP 地址',
                        hintText: '192.168.1.100',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _manualPortController,
                      decoration: const InputDecoration(
                        labelText: '端口',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final ip = _manualIpController.text.trim();
                    final port =
                        int.tryParse(_manualPortController.text.trim()) ?? 9527;
                    if (ip.isNotEmpty) {
                      _showPinDialog(DiscoveredDevice(
                        ip: ip,
                        port: port,
                        name: '$ip:$port',
                      ));
                    }
                  },
                  icon: const Icon(Icons.link),
                  label: const Text('手动连接'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showPinDialog(DiscoveredDevice device) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PinScreen(
          device: device,
          onConnected: _navigateToSend,
        ),
      ),
    );
  }
}

// ─── Private Widgets ─────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PairedDeviceTile extends StatelessWidget {
  final PairedDevice device;
  final VoidCallback onTap;
  const _PairedDeviceTile({required this.device, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.computer, color: Colors.green),
        title: Text(device.name),
        subtitle: Text('${device.ip}:${device.port}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _DiscoveredDeviceTile extends StatelessWidget {
  final DiscoveredDevice device;
  final VoidCallback onTap;
  const _DiscoveredDeviceTile({required this.device, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.computer, color: Colors.blue),
        title: Text(device.name),
        subtitle: Text('${device.ip}:${device.port}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
