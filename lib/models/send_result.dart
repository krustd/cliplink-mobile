enum SendStatus { idle, sending, sent, error }

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
    if (status == 'sent') {
      return SendResult(status: SendStatus.sent, id: id, message: '已发送');
    }
    return SendResult(status: SendStatus.sent, id: id, message: '已发送');
  }

  factory SendResult.fromNack(String id, String status, String message) {
    return SendResult(status: SendStatus.error, id: id, message: message);
  }
}
