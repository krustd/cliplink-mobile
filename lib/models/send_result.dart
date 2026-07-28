enum SendStatus {
  idle,
  sending,
  pasted,
  clipboardOnly,
  noFocus,
  error,
}

class SendResult {
  final SendStatus status;
  final String message;
  final String id;

  const SendResult({
    required this.status,
    this.message = '',
    this.id = '',
  });

  factory SendResult.fromAck(String id, String status) {
    switch (status) {
      case 'pasted':
        return SendResult(status: SendStatus.pasted, id: id, message: '已粘贴');
      case 'clipboard_only':
        return SendResult(
            status: SendStatus.clipboardOnly,
            id: id,
            message: '已写入剪贴板');
      default:
        return SendResult(
            status: SendStatus.clipboardOnly,
            id: id,
            message: '已写入剪贴板');
    }
  }

  factory SendResult.fromNack(String id, String status, String message) {
    switch (status) {
      case 'no_focus':
        return SendResult(
            status: SendStatus.noFocus, id: id, message: message);
      case 'empty':
        return SendResult(status: SendStatus.error, id: id, message: message);
      case 'too_large':
        return SendResult(status: SendStatus.error, id: id, message: message);
      default:
        return SendResult(status: SendStatus.error, id: id, message: message);
    }
  }
}
