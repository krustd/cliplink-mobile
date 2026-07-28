class DiscoveredDevice {
  final String ip;
  final int port;
  final String name;

  const DiscoveredDevice({
    required this.ip,
    required this.port,
    required this.name,
  });

  factory DiscoveredDevice.fromJson(Map<String, dynamic> json) {
    return DiscoveredDevice(
      ip: json['ip'] as String? ?? '',
      port: (json['tcp_port'] as num?)?.toInt() ?? 9527,
      name: json['name'] as String? ?? 'Unknown',
    );
  }

  /// Unique key for deduplication in device lists.
  String get key => '$ip:$port';

  @override
  bool operator ==(Object other) =>
      other is DiscoveredDevice && other.key == key;

  @override
  int get hashCode => key.hashCode;
}
