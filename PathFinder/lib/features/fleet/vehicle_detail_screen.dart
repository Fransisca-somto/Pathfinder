import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/constants/app_colors.dart';
import '../../core/models/vehicle_model.dart';
import '../../core/enums/vehicle_status.dart';
import '../../core/enums/user_role.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/custom_button.dart';

import '../../core/services/mqtt_service.dart';
import '../../core/services/api_client.dart';
import '../../core/providers/socket_provider.dart';
import 'widgets/camera_tab.dart';
import 'widgets/audio_tab.dart';
import 'widgets/events_tab.dart';
import 'vehicle_settings_screen.dart';

class VehicleDetailScreen extends ConsumerStatefulWidget {
  final VehicleModel vehicle;

  const VehicleDetailScreen({super.key, required this.vehicle});

  @override
  ConsumerState<VehicleDetailScreen> createState() => _VehicleDetailScreenState();
}

class _VehicleDetailScreenState extends ConsumerState<VehicleDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;


  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    
    // Subscribe to this vehicle's real-time updates when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(socketServiceProvider).subscribeVehicle(widget.vehicle.vehicleId);
    });
  }

  @override
  void dispose() {
    ref.read(socketServiceProvider).unsubscribeVehicle(widget.vehicle.vehicleId);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = ref.watch(currentUserProvider);
    final vehiclesAsync = ref.watch(vehiclesProvider);
    final vehicle = vehiclesAsync.value?.firstWhere(
      (v) => v.vehicleId == widget.vehicle.vehicleId, 
      orElse: () => widget.vehicle
    ) ?? widget.vehicle;

    // Listen for new media uploads from the IoT hardware
    ref.listen(newMediaProvider, (previous, next) {
      if (next.hasValue && next.value != null) {
        final data = next.value!;
        if (data['vehicleId'] == vehicle.vehicleId) {
          final type = data['type'] as String?;
          final mediaUrl = data['mediaUrl'] as String?;
          
          if (type == 'IMAGE' && mediaUrl != null) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('New Image Captured!'),
                content: Image.network(mediaUrl),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))
                ],
              ),
            );
          }
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(vehicle.vehicleName),
        backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        foregroundColor: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
        iconTheme: IconThemeData(color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Route History',
            onPressed: () {
              Navigator.pushNamed(
                context,
                '/route-history',
                arguments: vehicle,
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: AppColors.secondary,
          labelColor: AppColors.secondary,
          unselectedLabelColor: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
          tabs: const [
            Tab(text: 'Live'),
            Tab(text: 'Camera'),
            Tab(text: 'Audio'),
            Tab(text: 'Events'),
            Tab(text: 'Settings'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLiveTab(context, isDark, user, vehicle),
          CameraTab(vehicle: vehicle, isDark: isDark),
          AudioTab(vehicle: vehicle, isDark: isDark),
          EventsTab(vehicle: vehicle, isDark: isDark),
          VehicleSettingsScreen(vehicle: vehicle),
        ],
      ),
    );
  }

  Widget _buildLiveTab(BuildContext context, bool isDark, dynamic user, VehicleModel vehicle) {
    final lat = vehicle.currentLatitude;
    final lng = vehicle.currentLongitude;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mini Map Header
          SizedBox(
            height: 200,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(lat, lng),
                initialZoom: 15.0,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.pathfinder.app',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(lat, lng),
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.directions_car,
                        size: 32,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status & Info Banner
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Hero(
                          tag: 'vehicle_icon_${vehicle.vehicleId}',
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              vehicle.vehicleType == 'Car' ? Icons.directions_car : Icons.local_shipping,
                              color: isDark ? AppColors.textPrimaryDark : AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vehicle.plateNumber,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Type: ${vehicle.vehicleType} • Device: ${vehicle.deviceId}',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                              ),
                            ),
                            if (vehicle.assignedDrivers.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.person, size: 14, color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
                                  const SizedBox(width: 4),
                                  Text(
                                    vehicle.assignedDrivers.join(', '),
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: vehicle.currentStatus.color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: vehicle.currentStatus.color.withOpacity(0.5)),
                      ),
                      child: Text(
                        vehicle.currentStatus.displayName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: vehicle.currentStatus.color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                // Metrics Grid (StreamBuilder for mock MQTT)
                Text(
                  'Live Telemetry',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                  ),
                ),
                const SizedBox(height: 16),
                Builder(
                  builder: (context) {
                    final speed = vehicle.currentSpeed;
                    final battery = 12.0; // Simulated battery voltage
                    final gsm = vehicle.gpsSignalStrength.toDouble();
                    final isEngineCutOff = vehicle.isEngineLocked;
                    final isFuelCutOff = false; // Mock for now

                    return GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 1.5,
                      children: [
                        _buildMetricCard('Speed', '${speed.toStringAsFixed(1)} km/h', Icons.speed, isDark),
                        _buildMetricCard('Battery', '${battery.toStringAsFixed(1)}V', Icons.battery_charging_full, isDark),
                        _buildMetricCard('Engine Temp', '${vehicle.engineTemperature.toStringAsFixed(1)}°C', Icons.thermostat, isDark, isWarning: vehicle.engineTemperature > 105.0),
                        _buildMetricCard('Engine', isEngineCutOff ? 'CUT-OFF' : 'RUNNING', Icons.power_settings_new, isDark, isWarning: isEngineCutOff),
                      ],
                    );
                  }
                ),
                const SizedBox(height: 32),
                // Quick Actions
                Text(
                  'Quick Actions',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (user.role == UserRole.owner || user.role == UserRole.manager) ...[
                      Expanded(
                        child: CustomButton(
                          label: vehicle.isEngineLocked ? 'Unlock Engine' : 'Lock Engine',
                          onPressed: () async {
                            try {
                              // If it is locked, we send true to bypass. If unlocked, send false to lock.
                              final bypassState = vehicle.isEngineLocked;
                              await ref.read(apiClientProvider).post('/vehicles/${vehicle.vehicleId}/auth-bypass', {
                                'state': bypassState
                              });
                              
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Command sent to ${vehicle.vehicleName}'), backgroundColor: AppColors.success),
                              );
                              ref.invalidate(vehiclesProvider);
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to send command'), backgroundColor: AppColors.danger),
                              );
                            }
                          },
                          color: vehicle.isEngineLocked ? AppColors.success : AppColors.danger,
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                    Expanded(
                      child: CustomButton(
                        label: 'Driver Auth',
                        isOutlined: true,
                        icon: Icons.fingerprint,
                        onPressed: () {
                          Navigator.pushNamed(
                            context, 
                            '/driver-auth',
                            arguments: vehicle,
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                CustomButton(
                  label: 'View Route History',
                  icon: Icons.history,
                  isOutlined: true,
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      '/route-history',
                      arguments: vehicle,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, bool isDark, {bool isWarning = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isWarning ? AppColors.danger.withOpacity(0.1) : (isDark ? AppColors.surfaceDark : AppColors.surfaceLight),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isWarning ? AppColors.danger.withOpacity(0.3) : (isDark ? AppColors.dividerDark : AppColors.dividerLight)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: isWarning ? AppColors.danger : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isWarning ? AppColors.danger : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
            ),
          ),
        ],
      ),
    );
  }
}
