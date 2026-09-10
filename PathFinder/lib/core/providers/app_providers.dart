import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../models/vehicle_model.dart';
import '../models/alert_model.dart';
import '../models/zone_model.dart';
import '../models/trip_model.dart';
import '../models/fingerprint_profile_model.dart';
import '../enums/vehicle_status.dart';
import '../services/api_client.dart';
import '../utils/dummy_data.dart';
// Theme Provider
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.dark;

  void setTheme(ThemeMode mode) {
    state = mode;
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class DashboardIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setIndex(int index) => state = index;
}

final dashboardIndexProvider = NotifierProvider<DashboardIndexNotifier, int>(DashboardIndexNotifier.new);

// Auth/User Provider
class CurrentUserNotifier extends Notifier<UserModel?> {
  @override
  UserModel? build() {
    // Will be populated on login
    return null;
  }

  void setUser(UserModel? user) {
    state = user;
  }
}

final currentUserProvider = NotifierProvider<CurrentUserNotifier, UserModel?>(CurrentUserNotifier.new);

// Vehicles Provider
class VehiclesNotifier extends AsyncNotifier<List<VehicleModel>> {
  @override
  Future<List<VehicleModel>> build() async {
    return _fetchVehicles();
  }

  Future<List<VehicleModel>> _fetchVehicles() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.get('/vehicles');
      if (response is List) {
        return response.map<VehicleModel>((json) => VehicleModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching vehicles: $e');
      // Fall back to dummy data if API is unavailable
      return DummyData.vehicles;
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetchVehicles());
  }

  Future<void> updateVehicle(VehicleModel vehicle) async {
    try {
      final apiClient = ref.read(apiClientProvider);
      
      // Make the API call to update the backend
      await apiClient.put('/vehicles/${vehicle.vehicleId}', {
        'name': vehicle.vehicleName,
        'plate_number': vehicle.plateNumber,
        'type': vehicle.vehicleType,
        'update_interval': vehicle.updateInterval,
        'connection_mode': vehicle.connectionMode,
      });

      // Update the local state
      if (state.hasValue) {
        state = AsyncValue.data([
          for (final v in state.value!)
            if (v.vehicleId == vehicle.vehicleId) vehicle else v
        ]);
      }
    } catch (e) {
      print('Error updating vehicle: $e');
      throw Exception('Failed to save settings');
    }
  }

  Future<void> assignDriver(String vehicleId, String email) async {
    try {
      final apiClient = ref.read(apiClientProvider);
      
      await apiClient.post('/vehicles/$vehicleId/drivers', {
        'email': email.trim(),
      });
      // Optionally refresh to fetch joined drivers if the backend returns them,
      // but for now we just rely on the API success.
    } catch (e) {
      print('Error assigning driver: $e');
      throw Exception('Failed to assign driver $email');
    }
  }

  void addVehicle(VehicleModel vehicle) {
    if (state.hasValue) {
      state = AsyncValue.data([...state.value!, vehicle]);
    }
  }

  void updateTelemetry(Map<String, dynamic> data) {
    if (state.hasValue) {
      final deviceId = data['deviceId'];
      if (deviceId == null) return;
      
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      final speed = (data['speed'] as num?)?.toDouble();
      final temp = (data['temperature'] as num?)?.toDouble();
      final acc = data['acc'] as bool?;
      final batteryPct = data['battery'] as int?;
      final statusStr = data['status'] as String?;
      
      VehicleStatus? parsedStatus;
      if (statusStr != null) {
        parsedStatus = VehicleStatus.values.firstWhere(
          (e) => e.name.toLowerCase() == statusStr.toLowerCase(),
          orElse: () => VehicleStatus.offline,
        );
      }

      state = AsyncValue.data([
        for (final v in state.value!)
          if (v.deviceId.toLowerCase() == deviceId.toString().toLowerCase()) v.copyWith(
            currentLatitude: lat ?? v.currentLatitude,
            currentLongitude: lng ?? v.currentLongitude,
            currentSpeed: speed ?? v.currentSpeed,
            engineTemperature: temp ?? v.engineTemperature,
            currentStatus: parsedStatus ?? v.currentStatus,
            engineRunning: acc ?? v.engineRunning,
            batteryPercentage: batteryPct ?? v.batteryPercentage,
          ) else v
      ]);
    }
  }
}

final vehiclesProvider = AsyncNotifierProvider<VehiclesNotifier, List<VehicleModel>>(VehiclesNotifier.new);

// Alerts Provider
class AlertsNotifier extends AsyncNotifier<List<AlertModel>> {
  @override
  Future<List<AlertModel>> build() async {
    return _fetchAlerts();
  }

  Future<List<AlertModel>> _fetchAlerts() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.get('/alerts');
      if (response is List) {
        return response.map<AlertModel>((json) => AlertModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching alerts: $e');
      return DummyData.alerts;
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetchAlerts());
  }

  Future<void> markAsRead(String alertId) async {
    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.put('/alerts/$alertId/read', {});

      if (state.hasValue) {
        state = AsyncValue.data([
          for (final a in state.value!)
            if (a.alertId == alertId) a.copyWith(isRead: true) else a
        ]);
      }
    } catch (e) {
      print('Error marking alert as read: $e');
    }
  }

  Future<void> deleteAlert(String alertId) async {
    if (!state.hasValue) return;
    
    // Optimistic update: Remove from UI immediately to prevent Dismissible errors
    final previousAlerts = state.value!;
    state = AsyncValue.data(
      previousAlerts.where((a) => a.alertId != alertId).toList()
    );

    if (alertId.isEmpty) return;

    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.delete('/alerts/$alertId');
    } catch (e) {
      print('Error deleting alert: $e');
      // If API fails, revert the UI state
      state = AsyncValue.data(previousAlerts);
    }
  }

  void addAlert(Map<String, dynamic> data) {
    if (state.hasValue) {
      final newAlert = AlertModel.fromJson(data);
      state = AsyncValue.data([newAlert, ...state.value!]);
    }
  }
}

final alertsProvider = AsyncNotifierProvider<AlertsNotifier, List<AlertModel>>(AlertsNotifier.new);

// Zones Provider
class ZonesNotifier extends AsyncNotifier<List<ZoneModel>> {
  @override
  Future<List<ZoneModel>> build() async {
    return _fetchZones();
  }

  Future<List<ZoneModel>> _fetchZones() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.get('/zones');
      if (response is List) {
        return response.map<ZoneModel>((json) => ZoneModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching zones: $e');
      return DummyData.zones;
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetchZones());
  }

  Future<void> addZone(ZoneModel zone) async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.post('/zones', zone.toJson());
      
      if (state.hasValue) {
        final newZone = ZoneModel.fromJson(response);
        state = AsyncValue.data([...state.value!, newZone]);
      }
    } catch (e) {
      print('Error adding zone: $e');
      throw Exception('Failed to save zone');
    }
  }

  Future<void> updateZone(ZoneModel zone) async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.put('/zones/${zone.zoneId}', zone.toJson());
      
      if (state.hasValue) {
        final updatedZone = ZoneModel.fromJson(response);
        state = AsyncValue.data([
          for (final z in state.value!)
            if (z.zoneId == zone.zoneId) updatedZone else z
        ]);
      }
    } catch (e) {
      print('Error updating zone: $e');
      throw Exception('Failed to update zone');
    }
  }

  Future<void> deleteZone(String zoneId) async {
    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.delete('/zones/$zoneId');
      
      if (state.hasValue) {
        state = AsyncValue.data([
          for (final z in state.value!)
            if (z.zoneId != zoneId) z
        ]);
      }
    } catch (e) {
      print('Error deleting zone: $e');
      throw Exception('Failed to delete zone');
    }
  }
}

final zonesProvider = AsyncNotifierProvider<ZonesNotifier, List<ZoneModel>>(ZonesNotifier.new);

// Fingerprints Provider
final fingerprintsProvider = FutureProvider.family<List<FingerprintProfile>, String>((ref, vehicleId) async {
  try {
    final apiClient = ref.read(apiClientProvider);
    final response = await apiClient.get('/vehicles/$vehicleId/fingerprints');
    if (response is List) {
      return response.map<FingerprintProfile>((json) => FingerprintProfile.fromJson(json)).toList();
    }
    return [];
  } catch (e) {
    print('Error fetching fingerprints: $e');
    return [];
  }
});

// Trips Provider
final tripsProvider = FutureProvider.family<List<TripModel>, String>((ref, vehicleId) async {
  try {
    final apiClient = ref.read(apiClientProvider);
    final response = await apiClient.get('/vehicles/$vehicleId/trips');
    if (response is List) {
      return response.map<TripModel>((json) => TripModel.fromJson(json)).toList();
    }
    return [];
  } catch (e) {
    print('Error fetching trips: $e');
    return [];
  }
});
