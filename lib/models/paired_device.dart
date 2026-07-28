class PairedDevice {
  final String ip;
  final int port;
  final String name;
  final String pin;

  const PairedDevice({
    required this.ip,
    required this.port,
    required this.name,
    required this.pin,
  });

  Map<String, dynamic> toJson() => {
        'ip': ip,
        'port': port,
        'name': name,
        'pin': pin,
      };

  factory PairedDevice.fromJson(Map<String, dynamic> json) {
    return PairedDevice(
      ip: json['ip'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 9527,
      name: json['name'] as String? ?? 'Unknown',
      pin: json['pin'] as String? ?? '',
    );
  }

  String get key => '$ip:$port';
}
