import '../enums/vehicle_status.dart';

class VehicleModel {
  final String vehicleId;
  final String vehicleName;
  final String plateNumber;
  final String vehicleType;
  final List<String> assignedDrivers;
  final double currentLatitude;
  final double currentLongitude;
  final double currentSpeed;
  final VehicleStatus currentStatus;
  final DateTime lastUpdated;
  final double totalMileage;
  final List<String> safeZones;
  final String lastKnownLocation;
  final bool isEngineLocked;
  final String updateInterval;
  final String deviceId;
  final String connectionMode;
  final int gpsSignalStrength;
  final double engineTemperature;
  final double batteryVoltage;
  final int? _batteryPercentage;
  final bool engineRunning;

  const VehicleModel({
    required this.vehicleId,
    required this.vehicleName,
    required this.plateNumber,
    required this.vehicleType,
    this.assignedDrivers = const [],
    required this.currentLatitude,
    required this.currentLongitude,
    required this.currentSpeed,
    required this.currentStatus,
    required this.lastUpdated,
    required this.totalMileage,
    this.safeZones = const [],
    required this.lastKnownLocation,
    this.isEngineLocked = false,
    this.updateInterval = '5s',
    required this.deviceId,
    this.connectionMode = 'GPRS',
    this.gpsSignalStrength = 4,
    this.engineTemperature = 0.0,
    this.batteryVoltage = 12.0,
    int? batteryPercentage,
    this.engineRunning = false,
  }) : _batteryPercentage = batteryPercentage;

  int get batteryPercentage {
    if (_batteryPercentage != null) return _batteryPercentage!;
    if (batteryVoltage >= 12.6) return 100;
    if (batteryVoltage <= 11.9) return 0;
    return ((batteryVoltage - 11.9) / (12.6 - 11.9) * 100).round();
  }

  VehicleModel copyWith({
    String? vehicleId,
    String? vehicleName,
    String? plateNumber,
    String? vehicleType,
    List<String>? assignedDrivers,
    double? currentLatitude,
    double? currentLongitude,
    double? currentSpeed,
    VehicleStatus? currentStatus,
    DateTime? lastUpdated,
    double? totalMileage,
    List<String>? safeZones,
    String? lastKnownLocation,
    bool? isEngineLocked,
    String? updateInterval,
    String? deviceId,
    String? connectionMode,
    int? gpsSignalStrength,
    double? engineTemperature,
    double? batteryVoltage,
    int? batteryPercentage,
    bool? engineRunning,
  }) {
    return VehicleModel(
      vehicleId: vehicleId ?? this.vehicleId,
      vehicleName: vehicleName ?? this.vehicleName,
      plateNumber: plateNumber ?? this.plateNumber,
      vehicleType: vehicleType ?? this.vehicleType,
      assignedDrivers: assignedDrivers ?? this.assignedDrivers,
      currentLatitude: currentLatitude ?? this.currentLatitude,
      currentLongitude: currentLongitude ?? this.currentLongitude,
      currentSpeed: currentSpeed ?? this.currentSpeed,
      currentStatus: currentStatus ?? this.currentStatus,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      totalMileage: totalMileage ?? this.totalMileage,
      safeZones: safeZones ?? this.safeZones,
      lastKnownLocation: lastKnownLocation ?? this.lastKnownLocation,
      isEngineLocked: isEngineLocked ?? this.isEngineLocked,
      updateInterval: updateInterval ?? this.updateInterval,
      deviceId: deviceId ?? this.deviceId,
      connectionMode: connectionMode ?? this.connectionMode,
      gpsSignalStrength: gpsSignalStrength ?? this.gpsSignalStrength,
      engineTemperature: engineTemperature ?? this.engineTemperature,
      batteryVoltage: batteryVoltage ?? this.batteryVoltage,
      batteryPercentage: batteryPercentage ?? this._batteryPercentage,
      engineRunning: engineRunning ?? this.engineRunning,
    );
  }

  factory VehicleModel.fromJson(Map<String, dynamic> json) {
    // Determine the status from the API payload (e.g., if there's live telemetry included, or based on last update)
    final statusStr = json['status'] as String?;
    VehicleStatus status = VehicleStatus.parked;
    if (statusStr != null) {
      status = VehicleStatus.values.firstWhere(
        (e) => e.name.toLowerCase() == statusStr.toLowerCase(),
        orElse: () => VehicleStatus.offline,
      );
    }

    return VehicleModel(
      vehicleId: json['id'] ?? json['vehicleId'] ?? '',
      vehicleName: json['name'] ?? json['vehicleName'] ?? 'Unknown Vehicle',
      plateNumber: json['plate_number'] ?? json['plateNumber'] ?? '',
      vehicleType: json['type'] ?? json['vehicleType'] ?? 'Car',
      assignedDrivers: json['drivers'] != null ? List<String>.from(json['drivers'].map((d) => d['fullName'] ?? d['id'])) : [],
      currentLatitude: (json['current_latitude'] ?? json['currentLatitude'])?.toDouble() ?? 9.0820,
      currentLongitude: (json['current_longitude'] ?? json['currentLongitude'])?.toDouble() ?? 8.6753,
      currentSpeed: (json['current_speed'] ?? json['currentSpeed'])?.toDouble() ?? 0.0,
      currentStatus: status,
      lastUpdated: (json['created_at'] != null || json['createdAt'] != null) 
          ? DateTime.parse(json['created_at'] ?? json['createdAt']) 
          : DateTime.now(),
      totalMileage: (json['total_mileage'] ?? json['totalMileage'])?.toDouble() ?? 0.0,
      safeZones: json['safeZones'] != null ? List<String>.from(json['safeZones']) : [],
      lastKnownLocation: json['last_known_location'] ?? json['lastKnownLocation'] ?? 'Unknown',
      isEngineLocked: json['is_engine_locked'] ?? json['isEngineLocked'] ?? false,
      updateInterval: json['updateInterval'] ?? '5s',
      deviceId: json['device_id'] ?? json['deviceImei'] ?? json['deviceId'] ?? '',
      connectionMode: json['connectionMode'] ?? 'GPRS',
      gpsSignalStrength: json['gpsSignalStrength'] ?? 4,
      engineTemperature: (json['engine_temperature'] ?? 0.0).toDouble(),
      batteryVoltage: (json['battery_voltage'] ?? 12.0).toDouble(),
      batteryPercentage: json['battery'],
      engineRunning: json['acc'] ?? false,
    );
  }
}
