import 'package:flutter/services.dart';

/// Platform-channel based clipboard operations for images and files.
/// Falls back gracefully if the platform does not support the operation.
class ClipboardNative {
  static const _channel = MethodChannel('com.cliplink/clipboard');

  /// Write PNG image bytes to the system clipboard.
  /// Returns true on success, false if unsupported/failed.
  static Future<bool> writeImage(Uint8List pngBytes) async {
    try {
      final result = await _channel.invokeMethod<bool>('writeImage', {
        'bytes': pngBytes,
      });
      return result ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Write a file URI (file://) to the system clipboard.
  /// The file must already exist on disk at [filePath].
  /// Returns true on success, false if unsupported/failed.
  static Future<bool> writeFileUri(String filePath) async {
    try {
      final result = await _channel.invokeMethod<bool>('writeFileUri', {
        'path': filePath,
      });
      return result ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
