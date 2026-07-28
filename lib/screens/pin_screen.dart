import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/discovered_device.dart';
import '../providers/app_state.dart';

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
  final _focusNode = FocusNode();
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final pin = _pinController.text.trim();

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
        _error = 'PIN 码错误，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设备认证'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withAlpha(25),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.desktop_windows_rounded,
                    size: 36,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  widget.device.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.device.ip}:${widget.device.port}',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  '输入 PIN 码以连接',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _pinController,
                    focusNode: _focusNode,
                    obscureText: true,
                    textAlign: TextAlign.center,
                    enabled: !_connecting,
                    maxLength: 16,
                    buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 8,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    onSubmitted: (_) => _connect(),
                    decoration: InputDecoration(
                      hintText: '留空 = 无密码',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      errorText: _error,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '输入一次后将自动记住',
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: 200,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _connecting ? null : _connect,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: _connecting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text('连接', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
