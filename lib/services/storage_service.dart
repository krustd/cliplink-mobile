import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/paired_device.dart';

/// Persists paired device credentials locally.
class StorageService {
  static const _key = 'paired_devices';

  static Future<List<PairedDevice>> loadPairedDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw
        .map((s) => PairedDevice.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  static Future<void> savePairedDevice(PairedDevice device) async {
    final devices = await loadPairedDevices();
    devices.removeWhere((d) => d.key == device.key);
    devices.insert(0, device);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _key, devices.map((d) => jsonEncode(d.toJson())).toList());
  }

  static Future<void> removePairedDevice(String key) async {
    final devices = await loadPairedDevices();
    devices.removeWhere((d) => d.key == key);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _key, devices.map((d) => jsonEncode(d.toJson())).toList());
  }

  /// Find a paired device by IP:port key.
  static Future<PairedDevice?> findPaired(String key) async {
    final devices = await loadPairedDevices();
    try {
      return devices.firstWhere((d) => d.key == key);
    } catch (_) {
      return null;
    }
  }
}
