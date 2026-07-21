import '../enums/zone_type.dart';

class ZoneModel {
  final String zoneId;
  final String zoneName;
  final ZoneType zoneType;
  final ShapeType shapeType;
  final double centerLatitude;
  final double centerLongitude;
  final double radiusMeters;
  final List<List<double>> polygonPoints; // List of [lat, lon]
  final List<String> assignedVehicleIds;
  final DateTime createdAt;

  const ZoneModel({
    required this.zoneId,
    required this.zoneName,
    required this.zoneType,
    required this.shapeType,
    this.centerLatitude = 0.0,
    this.centerLongitude = 0.0,
    this.radiusMeters = 0.0,
    this.polygonPoints = const [],
    this.assignedVehicleIds = const [],
    required this.createdAt,
  });

  factory ZoneModel.fromJson(Map<String, dynamic> json) {
    final coords = json['coordinates'] as Map<String, dynamic>? ?? {};
    final polyPoints = (coords['polygonPoints'] as List<dynamic>?)
            ?.map((e) => (e as List<dynamic>).map((c) => (c as num).toDouble()).toList())
            .toList() ??
        [];

    return ZoneModel(
      zoneId: json['id'] ?? '',
      zoneName: json['name'] ?? '',
      zoneType: ZoneType.values.firstWhere(
        (e) => e.name.toLowerCase() == (json['type'] as String?)?.toLowerCase(),
        orElse: () => ZoneType.safe,
      ),
      shapeType: ShapeType.values.firstWhere(
        (e) => e.name.toLowerCase() == (json['shape'] as String?)?.toLowerCase(),
        orElse: () => ShapeType.circle,
      ),
      centerLatitude: (coords['centerLatitude'] as num?)?.toDouble() ?? 0.0,
      centerLongitude: (coords['centerLongitude'] as num?)?.toDouble() ?? 0.0,
      radiusMeters: (json['radius'] as num?)?.toDouble() ?? 0.0,
      polygonPoints: polyPoints,
      assignedVehicleIds: const [], // We'll manage this via a separate join table later if needed
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': zoneName,
      'type': zoneType.name,
      'shape': shapeType.name,
      'radius': radiusMeters,
      'is_active': true,
      'coordinates': {
        'centerLatitude': centerLatitude,
        'centerLongitude': centerLongitude,
        'polygonPoints': polygonPoints,
      }
    };
  }
}
