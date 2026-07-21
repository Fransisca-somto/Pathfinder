class FingerprintProfile {
  final String id;
  final String vehicleId;
  final String driverName;
  final int slotId;
  final String status;
  final bool isActive;
  final DateTime createdAt;

  FingerprintProfile({
    required this.id,
    required this.vehicleId,
    required this.driverName,
    required this.slotId,
    required this.status,
    required this.isActive,
    required this.createdAt,
  });

  factory FingerprintProfile.fromJson(Map<String, dynamic> json) {
    return FingerprintProfile(
      id: json['id'] ?? '',
      vehicleId: json['vehicle_id'] ?? '',
      driverName: json['driver_name'] ?? 'Unknown',
      slotId: json['slot_id'] ?? 1,
      status: json['status'] ?? 'pending',
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.now(),
    );
  }
}
