import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/send_result.dart';
import '../providers/app_state.dart';
import 'devices_screen.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({super.key});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

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
    final theme = Theme.of(context);

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
                  boxShadow: [
                    BoxShadow(
                      color: (state.isConnected ? Colors.green : Colors.red)
                          .withAlpha(100),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  state.isConnected ? state.connectedDeviceName : '未连接',
                  style: const TextStyle(fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              context.read<AppState>().disconnect();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const DevicesScreen()),
              );
            },
            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
            label: const Text('切换'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ── Status chip ───────────────────────────────────────
            Consumer<AppState>(
              builder: (_, state, _) => _StatusChip(
                status: state.sendStatus,
                message: state.sendMessage,
              ),
            ),

            const SizedBox(height: 14),

            // ── Text input ─────────────────────────────────────────
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                  color: Colors.grey.shade50,
                ),
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontSize: 16, height: 1.5),
                  decoration: const InputDecoration(
                    hintText: '输入要发送到电脑的文本...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                  ),
                  autofocus: true,
                ),
              ),
            ),

            const SizedBox(height: 14),

            // ── Send button ────────────────────────────────────────
            Consumer<AppState>(
              builder: (context, state, _) {
                final sending = state.sendStatus == SendStatus.sending;
                final connected = state.isConnected;

                return SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: connected && !sending ? _send : null,
                    icon: sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 20),
                    label: Text(sending ? '发送中...' : '发送到电脑'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade200,
                      disabledForegroundColor: Colors.grey.shade400,
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Animated status chip showing send result.
class _StatusChip extends StatelessWidget {
  final SendStatus status;
  final String message;

  const _StatusChip({required this.status, required this.message});

  @override
  Widget build(BuildContext context) {
    if (status == SendStatus.idle) return const SizedBox(height: 4);

    final (bgColor, fgColor, icon) = switch (status) {
      SendStatus.sending =>
        (Colors.blue.shade50, Colors.blue.shade700, Icons.hourglass_top_rounded),
      SendStatus.pasted =>
        (Colors.green.shade50, Colors.green.shade700, Icons.check_circle_rounded),
      SendStatus.noFocus =>
        (Colors.red.shade50, Colors.red.shade700, Icons.error_outline_rounded),
      SendStatus.error =>
        (Colors.red.shade50, Colors.red.shade700, Icons.error_rounded),
      _ => (Colors.grey.shade100, Colors.grey.shade600, Icons.info_rounded),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fgColor.withAlpha(50)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: fgColor, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: TextStyle(
                color: fgColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
