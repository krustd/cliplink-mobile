import 'package:flutter/services.dart';

/// Saves files to the public Downloads directory via platform channel.
class FileSaver {
  static const _channel = MethodChannel('com.cliplink/files');

  /// Save [bytes] as [fileName] to the Downloads folder.
  /// Returns true on success.
  static Future<bool> saveToDownloads(String fileName, Uint8List bytes) async {
    try {
      final result = await _channel.invokeMethod<bool>('saveFile', {
        'fileName': fileName,
        'bytes': bytes,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}
