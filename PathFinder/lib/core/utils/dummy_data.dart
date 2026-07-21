import '../models/user_model.dart';
import '../models/vehicle_model.dart';
import '../models/zone_model.dart';
import '../models/alert_model.dart';
import '../models/waypoint_model.dart';
import '../enums/user_role.dart';
import '../enums/vehicle_status.dart';
import '../enums/alert_type.dart';
import '../enums/zone_type.dart';

class DummyData {
  static final List<UserModel> users = [
    UserModel(
      userId: 'U001',
      fullName: 'Chukwuemeka Owner',
      email: 'owner@tracker.com',
      phone: '+2348031234567',
      role: UserRole.owner,
      createdAt: DateTime.now().subtract(const Duration(days: 365)),
    ),
    UserModel(
      userId: 'U002',
      fullName: 'Ngozi Manager',
      email: 'manager@tracker.com',
      phone: '+2348051234567',
      role: UserRole.manager,
      createdAt: DateTime.now().subtract(const Duration(days: 180)),
    ),
    UserModel(
      userId: 'U003',
      fullName: 'Tunde Driver',
      email: 'driver@tracker.com',
      phone: '+2348091234567',
      role: UserRole.driver,
      assignedVehicles: ['V001'],
      createdAt: DateTime.now().subtract(const Duration(days: 90)),
    ),
  ];

  static final List<VehicleModel> vehicles = [
    VehicleModel(
      vehicleId: 'V001',
      vehicleName: 'Toyota Hilux',
      plateNumber: 'AWK 234 AB',
      vehicleType: 'Truck',
      assignedDrivers: const ['Tunde Driver'],
      currentLatitude: 6.2209,
      currentLongitude: 7.0722, // Awka
      currentSpeed: 45.5,
      currentStatus: VehicleStatus.moving,
      lastUpdated: DateTime.now().subtract(const Duration(seconds: 5)),
      totalMileage: 12500.5,
      lastKnownLocation: 'Awka, Anambra',
      deviceId: 'ESP32-AWK-01',
    ),
    VehicleModel(
      vehicleId: 'V002',
      vehicleName: 'Toyota Corolla',
      plateNumber: 'EN 456 CD',
      vehicleType: 'Car',
      currentLatitude: 6.4584,
      currentLongitude: 7.5464, // Enugu
      currentSpeed: 0.0,
      currentStatus: VehicleStatus.parked,
      lastUpdated: DateTime.now().subtract(const Duration(minutes: 10)),
      totalMileage: 45000.2,
      lastKnownLocation: 'Enugu GRA, Enugu',
      deviceId: 'ESP32-ENU-02',
    ),
    VehicleModel(
      vehicleId: 'V003',
      vehicleName: 'Nissan Urvan',
      plateNumber: 'LG 789 EF',
      vehicleType: 'Van',
      currentLatitude: 6.4541,
      currentLongitude: 3.3947, // Lagos
      currentSpeed: 85.0,
      currentStatus: VehicleStatus.alarm,
      lastUpdated: DateTime.now().subtract(const Duration(seconds: 2)),
      totalMileage: 8500.0,
      lastKnownLocation: 'Lagos Island, Lagos',
      deviceId: 'ESP32-LAG-03',
      isEngineLocked: true,
    ),
  ];

  static final List<AlertModel> alerts = [
    AlertModel(
      alertId: 'A001',
      alertType: AlertType.zoneExit,
      vehicleId: 'V001',
      vehicleName: 'Toyota Hilux',
      message: 'Vehicle left Awka Depot Safe Zone.',
      timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
      requiresAction: true,
      actionType: 'lock_engine',
    ),
    AlertModel(
      alertId: 'A002',
      alertType: AlertType.speed,
      vehicleId: 'V003',
      vehicleName: 'Nissan Urvan',
      message: 'Speed limit exceeded: 110 km/h.',
      timestamp: DateTime.now().subtract(const Duration(hours: 1)),
      isRead: true,
    ),
  ];

  static final List<ZoneModel> zones = [
    ZoneModel(
      zoneId: 'Z001',
      zoneName: 'Awka Depot',
      zoneType: ZoneType.safe,
      shapeType: ShapeType.circle,
      centerLatitude: 6.2200,
      centerLongitude: 7.0700,
      radiusMeters: 500.0,
      assignedVehicleIds: const ['V001', 'V002'],
      createdAt: DateTime.now().subtract(const Duration(days: 30)),
    ),
  ];
}
