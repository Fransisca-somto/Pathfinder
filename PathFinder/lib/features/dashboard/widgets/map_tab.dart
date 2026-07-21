import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/socket_provider.dart';
import '../../../core/models/vehicle_model.dart';
import '../../../core/enums/zone_type.dart';
import '../../../core/enums/vehicle_status.dart';
import 'vehicle_quick_card.dart';

class MapTab extends ConsumerStatefulWidget {
  const MapTab({super.key});

  @override
  ConsumerState<MapTab> createState() => _MapTabState();
}

class _MapTabState extends ConsumerState<MapTab> {
  final MapController _mapController = MapController();
  VehicleModel? _selectedVehicle;

  // Center of Nigeria
  static const _center = LatLng(9.0820, 8.6753);


  @override
  Widget build(BuildContext context) {
    final vehiclesAsync = ref.watch(vehiclesProvider);
    final zonesAsync = ref.watch(zonesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Listen to live telemetry to update locations reactively for map panning ONLY
    ref.listen(liveTelemetryProvider, (previous, next) {
      if (next.hasValue && next.value != null) {
        final data = next.value!;
        final dId = data['deviceId'];
        final lat = (data['lat'] as num?)?.toDouble();
        final lng = (data['lng'] as num?)?.toDouble();
        if (dId != null && lat != null && lng != null) {
          if (_selectedVehicle != null && _selectedVehicle!.deviceId == dId) {
            _mapController.move(LatLng(lat, lng), _mapController.camera.zoom);
          }
        }
      }
    });

    return vehiclesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
      data: (vehicles) {
        final zones = zonesAsync.value ?? [];
        
        // Create markers from vehicles
        final List<Marker> markers = vehicles.map((vehicle) {
          double lat = vehicle.currentLatitude;
          double lng = vehicle.currentLongitude;

          return Marker(
            point: LatLng(lat, lng),
            width: 40,
            height: 40,
            child: GestureDetector(
              onTap: () {
                setState(() => _selectedVehicle = vehicle);
                _mapController.move(LatLng(vehicle.currentLatitude, vehicle.currentLongitude), 14.0);
              },
              child: Icon(
                Icons.directions_car,
                size: 32,
                color: vehicle.currentStatus == VehicleStatus.moving 
                    ? Colors.green 
                    : vehicle.currentStatus == VehicleStatus.alarm 
                        ? Colors.red 
                        : vehicle.currentStatus == VehicleStatus.parked 
                            ? Colors.orange 
                            : Colors.grey,
              ),
            ),
          );
        }).toList();

    // Create circles from zones
    final List<CircleMarker> circles = zones
        .where((z) => z.shapeType == ShapeType.circle)
        .map((zone) {
      return CircleMarker(
        point: LatLng(zone.centerLatitude, zone.centerLongitude),
        radius: zone.radiusMeters,
        color: zone.zoneType.color.withOpacity(0.2),
        borderColor: zone.zoneType.color,
        borderStrokeWidth: 2,
        useRadiusInMeter: true,
      );
    }).toList();

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _center,
            initialZoom: 6.0,
            onTap: (_, __) => setState(() => _selectedVehicle = null),
          ),
          children: [
            TileLayer(
              // Using standard free OSM tiles
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.pathfinder.app',
            ),
            if (circles.isNotEmpty) CircleLayer(circles: circles),
            if (markers.isNotEmpty) MarkerLayer(markers: markers),
          ],
        ),
        
        // Floating Controls (Zoom/Recenter)
        Positioned(
          right: 16,
          bottom: _selectedVehicle != null ? 300 : 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: 'zoomInGMap',
                backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                onPressed: () {
                  _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1);
                },
                child: Icon(Icons.add, color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'zoomOutGMap',
                backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                onPressed: () {
                  _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1);
                },
                child: Icon(Icons.remove, color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
              ),
              const SizedBox(height: 8),
              FloatingActionButton(
                heroTag: 'recenterGMap',
                backgroundColor: AppColors.primary,
                onPressed: () {
                  setState(() => _selectedVehicle = null);
                  _mapController.move(_center, 6.0);
                },
                child: const Icon(Icons.crop_free, color: Colors.white),
              ),
            ],
          ),
        ),

        // Selected Vehicle Info Card
        if (_selectedVehicle != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VehicleQuickCard(
              vehicle: _selectedVehicle!,
              onClose: () => setState(() => _selectedVehicle = null),
            ),
          )
      ],
    );
    },
    );
  }
}
