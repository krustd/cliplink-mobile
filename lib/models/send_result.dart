enum SendStatus {
  idle,
  sending,
  pasted,
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
    if (status == 'pasted') {
      return SendResult(status: SendStatus.pasted, id: id, message: '已粘贴');
    }
    return SendResult(status: SendStatus.pasted, id: id, message: '已粘贴');
  }

  factory SendResult.fromNack(String id, String status, String message) {
    switch (status) {
      case 'no_focus':
        return SendResult(status: SendStatus.noFocus, id: id, message: message);
      case 'paste_error':
        return SendResult(status: SendStatus.error, id: id, message: message);
      case 'empty':
        return SendResult(status: SendStatus.error, id: id, message: message);
      case 'too_large':
        return SendResult(status: SendStatus.error, id: id, message: message);
      default:
        return SendResult(status: SendStatus.error, id: id, message: message);
    }
  }
}
