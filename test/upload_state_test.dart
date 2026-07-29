import 'package:clip_link_mobile/models/upload_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selected and active uploads block conflicting actions', () {
    for (final status in [
      UploadStatus.selecting,
      UploadStatus.ready,
      UploadStatus.uploading,
    ]) {
      expect(UploadState(status: status).blocksOtherActions, isTrue);
    }
    for (final status in [
      UploadStatus.idle,
      UploadStatus.sent,
      UploadStatus.error,
      UploadStatus.cancelled,
    ]) {
      expect(UploadState(status: status).blocksOtherActions, isFalse);
    }
  });

  test('upload progress derives from daemon-confirmed bytes', () {
    const state = UploadState(totalBytes: 100, receivedBytes: 35);
    expect(state.progress, 0.35);
  });
}
