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
  bool _dialogShown = false;

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

  void _sendEnter() {
    context.read<AppState>().sendEnter();
  }

  void _fetchClipboard() {
    _dialogShown = false;
    context.read<AppState>().queryClipboard();
  }

  /// Show a confirmation dialog for clipboard content the user must approve.
  void _showClipboardConfirm(AppState state) {
    final info = state.clipboardInfo;
    if (info == null) return;

    final contentType = info['content_type'] as String? ?? '';
    String title;
    String body;

    switch (contentType) {
      case 'text':
        final sizeBytes = (info['size_bytes'] as num?)?.toInt() ?? 0;
        title = '获取文本';
        body = '电脑剪贴板有文本内容，大小约 ${_formatSize(sizeBytes)}，是否获取？';
        break;
      case 'image':
        final sizeBytes = (info['size_bytes'] as num?)?.toInt() ?? 0;
        final width = info['width'] as int?;
        final height = info['height'] as int?;
        final dims = (width != null && height != null) ? '$width\u00d7$height' : '';
        title = '获取图片';
        body = '电脑剪贴板有图片${dims.isNotEmpty ? ' ($dims)' : ''}，大小约 ${_formatSize(sizeBytes)}，是否获取？';
        break;
      case 'file':
        final files = info['files'] as List<dynamic>? ?? [];
        if (files.isEmpty) {
          title = '获取文件';
          body = '电脑剪贴板上有文件，是否获取？';
        } else if (files.length == 1) {
          final name = files[0]['name'] as String? ?? '';
          final size = (files[0]['size'] as num?)?.toInt() ?? 0;
          title = '获取文件';
          body = '$name (${_formatSize(size)})，是否获取？';
        } else {
          title = '获取文件';
          body = '电脑剪贴板上有 ${files.length} 个文件，是否获取？';
        }
        break;
      default:
        return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              state.cancelClipboardFetch();
            },
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              state.confirmClipboardFetch();
            },
            child: const Text('获取'),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
          Consumer<AppState>(
            builder: (_, state, _) => IconButton(
              onPressed: state.isConnected &&
                      state.clipboardStatus != ClipboardFetchStatus.querying &&
                      state.clipboardStatus != ClipboardFetchStatus.fetching
                  ? _fetchClipboard
                  : null,
              icon: state.clipboardStatus == ClipboardFetchStatus.querying ||
                      state.clipboardStatus == ClipboardFetchStatus.fetching
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.content_paste_rounded),
              tooltip: '获取剪贴板',
            ),
          ),
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
              builder: (_, state, _) {
                // Show clipboard status when active, else send status
                if (state.clipboardStatus != ClipboardFetchStatus.idle) {
                  return _ClipboardStatusChip(
                    status: state.clipboardStatus,
                    message: state.clipboardMessage,
                  );
                }
                return _StatusChip(
                  status: state.sendStatus,
                  message: state.sendMessage,
                );
              },
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

            // ── Action buttons ───────────────────────────────────────
            Consumer<AppState>(
              builder: (context, state, _) {
                final sending = state.sendStatus == SendStatus.sending;
                final connected = state.isConnected;

                // Reset dialog flag when clipboard state is cleared
                if (state.clipboardInfo == null) {
                  _dialogShown = false;
                }
                // Check if we need to show clipboard confirmation
                if (state.clipboardInfo != null &&
                    state.clipboardStatus == ClipboardFetchStatus.done) {
                  final info = state.clipboardInfo!;
                  final contentType = info['content_type'] as String? ?? '';
                  // Text ≤ 512KB was auto-fetched; other types need confirmation
                  final needsConfirm = contentType != 'text' ||
                      ((info['size_bytes'] as num?)?.toInt() ?? 0) > 524288;

                  if (needsConfirm && !_dialogShown) {
                    _dialogShown = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _showClipboardConfirm(state);
                    });
                  }
                }

                return Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: SizedBox(
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
                          label: Text(sending ? '发送中...' : '发送文本'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey.shade200,
                            disabledForegroundColor: Colors.grey.shade400,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 64,
                      height: 54,
                      child: OutlinedButton(
                        onPressed: connected && !sending ? _sendEnter : null,
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Icon(Icons.keyboard_return, size: 24),
                      ),
                    ),
                  ],
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
      SendStatus.sent =>
        (Colors.green.shade50, Colors.green.shade700, Icons.check_circle_rounded),
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

/// Clipboard-specific status chip.
class _ClipboardStatusChip extends StatelessWidget {
  final ClipboardFetchStatus status;
  final String message;

  const _ClipboardStatusChip({required this.status, required this.message});

  @override
  Widget build(BuildContext context) {
    if (status == ClipboardFetchStatus.idle) return const SizedBox(height: 4);

    final (bgColor, fgColor, icon) = switch (status) {
      ClipboardFetchStatus.querying || ClipboardFetchStatus.fetching =>
        (Colors.blue.shade50, Colors.blue.shade700, Icons.cloud_download_rounded),
      ClipboardFetchStatus.done =>
        (Colors.green.shade50, Colors.green.shade700, Icons.check_circle_rounded),
      ClipboardFetchStatus.error =>
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
          status == ClipboardFetchStatus.querying || status == ClipboardFetchStatus.fetching
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, color: fgColor, size: 18),
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
