import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/send_result.dart';
import '../providers/app_state.dart';
import 'devices_screen.dart';

/// Main send screen shown after connecting to a device.
class SendScreen extends StatefulWidget {
  const SendScreen({super.key});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    context.read<AppState>().send(text);
    _textController.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<AppState>(
          builder: (_, state, _) => Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: state.isConnected ? Colors.green : Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.isConnected ? state.connectedDeviceName : '未连接',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: '切换设备',
            onPressed: () {
              context.read<AppState>().disconnect();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const DevicesScreen()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Status indicator
            Consumer<AppState>(
              builder: (_, state, _) => _StatusBanner(
                status: state.sendStatus,
                message: state.sendMessage,
              ),
            ),
            const SizedBox(height: 12),

            // Text input
            Expanded(
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: '输入要发送到电脑的文本...',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                autofocus: true,
              ),
            ),
            const SizedBox(height: 12),

            // Send button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: Consumer<AppState>(
                builder: (context, state, _) {
                  final sending = state.sendStatus == SendStatus.sending;
                  final connected = state.isConnected;
                  return ElevatedButton.icon(
                    onPressed: connected && !sending ? _send : null,
                    icon: sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send),
                    label: Text(sending ? '发送中...' : '发送'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Status banner showing the result of the last send.
class _StatusBanner extends StatelessWidget {
  final SendStatus status;
  final String message;
  const _StatusBanner({required this.status, required this.message});

  @override
  Widget build(BuildContext context) {
    if (status == SendStatus.idle) return const SizedBox.shrink();

    final (color, icon) = switch (status) {
      SendStatus.sending => (Colors.blue, Icons.hourglass_top),
      SendStatus.pasted => (Colors.green, Icons.check_circle),
      SendStatus.clipboardOnly => (Colors.orange, Icons.content_copy),
      SendStatus.noFocus => (Colors.red, Icons.error_outline),
      SendStatus.error => (Colors.red, Icons.error),
      _ => (Colors.grey, Icons.info),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(76)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
