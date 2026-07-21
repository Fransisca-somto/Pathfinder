class WaypointModel {
  final String waypointId;
  final String vehicleId;
  final double latitude;
  final double longitude;
  final double speed;
  final DateTime timestamp;
  final String status;
  final String eventNote;

  const WaypointModel({
    required this.waypointId,
    required this.vehicleId,
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.timestamp,
    required this.status,
    this.eventNote = '',
  });
}
