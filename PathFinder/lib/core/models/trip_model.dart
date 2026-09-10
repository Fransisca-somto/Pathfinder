class TripModel {
  final String id;
  final String vehicleId;
  final DateTime startTime;
  final DateTime? endTime;
  final double startLat;
  final double startLng;
  final double? endLat;
  final double? endLng;
  final String? startAddress;
  final String? endAddress;
  final double? distanceKm;
  final int? durationMins;
  final List<List<double>> routePath;

  TripModel({
    required this.id,
    required this.vehicleId,
    required this.startTime,
    this.endTime,
    required this.startLat,
    required this.startLng,
    this.endLat,
    this.endLng,
    this.startAddress,
    this.endAddress,
    this.distanceKm,
    this.durationMins,
    this.routePath = const [],
  });

  factory TripModel.fromJson(Map<String, dynamic> json) {
    return TripModel(
      id: json['id'],
      vehicleId: json['vehicle_id'],
      startTime: DateTime.parse(json['start_time']),
      endTime: json['end_time'] != null ? DateTime.parse(json['end_time']) : null,
      startLat: json['start_lat'].toDouble(),
      startLng: json['start_lng'].toDouble(),
      endLat: json['end_lat']?.toDouble(),
      endLng: json['end_lng']?.toDouble(),
      startAddress: json['start_address'],
      endAddress: json['end_address'],
      distanceKm: json['distance_km']?.toDouble(),
      durationMins: json['duration_mins'],
      routePath: json['route_path'] != null 
          ? (json['route_path'] as List).map((point) => [
              (point[0] as num).toDouble(),
              (point[1] as num).toDouble(),
            ]).toList()
          : [],
    );
  }
}
