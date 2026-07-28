import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/discovered_device.dart';
import '../providers/app_state.dart';

/// PIN entry screen for first-time connection to a device.
class PinScreen extends StatefulWidget {
  final DiscoveredDevice device;
  final VoidCallback onConnected;

  const PinScreen({
    super.key,
    required this.device,
    required this.onConnected,
  });

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  final _pinController = TextEditingController();
  bool _connecting = false;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final pin = _pinController.text.trim();
    if (pin.isEmpty) {
      setState(() => _error = '请输入 PIN 码');
      return;
    }

    setState(() {
      _connecting = true;
      _error = null;
    });

    final state = context.read<AppState>();
    final ok = await state.connectWithPin(widget.device, pin);

    if (!mounted) return;

    if (ok) {
      widget.onConnected();
    } else {
      setState(() {
        _connecting = false;
        _error = '认证失败，请检查 PIN 码';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('输入 PIN 码')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Device info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Icon(Icons.computer, size: 48, color: Colors.blue),
                    const SizedBox(height: 8),
                    Text(
                      widget.device.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${widget.device.ip}:${widget.device.port}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // PIN input
            TextField(
              controller: _pinController,
              decoration: InputDecoration(
                labelText: 'PIN 码',
                hintText: '请输入电脑端配置的 PIN 码',
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
              keyboardType: TextInputType.number,
              obscureText: true,
              enabled: !_connecting,
              onSubmitted: (_) => _connect(),
            ),

            const SizedBox(height: 8),
            Text(
              '输入一次后将会记住，以后可直接连接',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),

            const SizedBox(height: 24),

            // Connect button
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _connecting ? null : _connect,
                child: _connecting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('连接'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
