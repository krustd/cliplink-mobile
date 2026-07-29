enum UploadKind { image, file }

enum UploadStatus { idle, selecting, ready, uploading, sent, error, cancelled }

class UploadState {
  final UploadStatus status;
  final UploadKind? kind;
  final String filename;
  final int totalBytes;
  final int receivedBytes;
  final String id;
  final String message;

  const UploadState({
    this.status = UploadStatus.idle,
    this.kind,
    this.filename = '',
    this.totalBytes = 0,
    this.receivedBytes = 0,
    this.id = '',
    this.message = '',
  });

  bool get isActive =>
      status == UploadStatus.selecting || status == UploadStatus.uploading;
  bool get isReady => status == UploadStatus.ready;
  double get progress => totalBytes == 0 ? 0 : receivedBytes / totalBytes;

  bool get blocksOtherActions =>
      status == UploadStatus.selecting ||
      status == UploadStatus.ready ||
      status == UploadStatus.uploading;

  UploadState copyWith({
    UploadStatus? status,
    UploadKind? kind,
    String? filename,
    int? totalBytes,
    int? receivedBytes,
    String? id,
    String? message,
  }) {
    return UploadState(
      status: status ?? this.status,
      kind: kind ?? this.kind,
      filename: filename ?? this.filename,
      totalBytes: totalBytes ?? this.totalBytes,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      id: id ?? this.id,
      message: message ?? this.message,
    );
  }
}
