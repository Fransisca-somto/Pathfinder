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
  bool _isLockCommandPending = false;


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
    
    final fingerprintsAsync = ref.watch(fingerprintsProvider(widget.vehicle.vehicleId));
    final fingerprints = fingerprintsAsync.value ?? [];
    
    String driverDisplay = 'No Driver';
    if (vehicle.currentDriverId > 0) {
      final match = fingerprints.where((f) => f.slotId == vehicle.currentDriverId).firstOrNull;
      driverDisplay = match?.driverName ?? 'Driver ${vehicle.currentDriverId}';
    } else if (vehicle.assignedDrivers.isNotEmpty) {
      driverDisplay = 'Assigned: ${vehicle.assignedDrivers.join(', ')}';
    }


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
          _buildLiveTab(context, isDark, user, vehicle, driverDisplay),
          CameraTab(vehicle: vehicle, isDark: isDark),
          AudioTab(vehicle: vehicle, isDark: isDark),
          EventsTab(vehicle: vehicle, isDark: isDark),
          VehicleSettingsScreen(vehicle: vehicle),
        ],
      ),
    );
  }

  Widget _buildLiveTab(BuildContext context, bool isDark, dynamic user, VehicleModel vehicle, String driverDisplay) {
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
                            if (driverDisplay != 'No Driver') ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    vehicle.currentDriverId > 0 ? Icons.how_to_reg : Icons.person, 
                                    size: 14, 
                                    color: vehicle.currentDriverId > 0 
                                        ? AppColors.success 
                                        : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    driverDisplay,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: vehicle.currentDriverId > 0 ? FontWeight.bold : FontWeight.normal,
                                      color: vehicle.currentDriverId > 0 
                                          ? AppColors.success
                                          : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
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
                    final batteryVoltage = vehicle.batteryVoltage;
                    final batteryPct = vehicle.batteryPercentage;
                    final gsm = vehicle.gpsSignalStrength.toDouble();
                    final isEngineCutOff = vehicle.isEngineLocked;
                    final isFuelCutOff = false; // Mock for now

                    // Battery display: show "Charging" when alternator is running
                    final batteryDisplay = vehicle.charging 
                        ? '${batteryVoltage.toStringAsFixed(1)}V (Charging)'
                        : '${batteryVoltage.toStringAsFixed(1)}V ($batteryPct%)';

                    return Column(
                      children: [
                        // Power cut warning banner
                        if (vehicle.powerCut)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.danger.withOpacity(0.5)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.power_off, color: AppColors.danger),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '⚠ Vehicle Power Disconnected — Possible tampering or theft',
                                    style: TextStyle(
                                      color: AppColors.danger,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 1.5,
                          children: [
                            _buildMetricCard('Speed', '${speed.toStringAsFixed(1)} km/h', Icons.speed, isDark),
                            _buildMetricCard('Battery', batteryDisplay, vehicle.charging ? Icons.battery_charging_full : Icons.battery_full, isDark, isWarning: vehicle.powerCut),
                            _buildMetricCard('Engine Temp', vehicle.engineTemperature != null ? '${vehicle.engineTemperature!.toStringAsFixed(1)}°C' : 'N/A', Icons.thermostat, isDark, isWarning: (vehicle.engineTemperature ?? 0) > 105.0),
                            _buildMetricCard('Engine', vehicle.engineRunning ? 'RUNNING' : 'OFF', Icons.power_settings_new, isDark, isWarning: vehicle.isEngineLocked),
                          ],
                        ),
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
                          label: _isLockCommandPending 
                              ? 'Pending...' 
                              : (vehicle.isEngineLocked ? 'Unlock Engine' : 'Lock Engine'),
                          onPressed: _isLockCommandPending ? () {} : () async {
                            if (vehicle.currentStatus == VehicleStatus.offline) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Tracker is offline. Please wait until it comes online.'), backgroundColor: AppColors.warning),
                              );
                              return;
                            }
                            try {
                              setState(() {
                                _isLockCommandPending = true;
                              });
                              // If it is locked, we send true to bypass. If unlocked, send false to lock.
                              final bypassState = vehicle.isEngineLocked;
                              await ref.read(apiClientProvider).post('/vehicles/${vehicle.vehicleId}/auth-bypass', {
                                'state': bypassState
                              });
                              
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Command sent to ${vehicle.vehicleName}'), backgroundColor: AppColors.success),
                              );
                              // We no longer invalidate the whole provider here since it doesn't optimistically update DB.
                              // The state will clear itself after 5 seconds to prevent getting stuck if no reply arrives.
                              Future.delayed(const Duration(seconds: 5), () {
                                if (mounted) {
                                  setState(() {
                                    _isLockCommandPending = false;
                                  });
                                }
                              });
                            } catch (e) {
                              setState(() {
                                _isLockCommandPending = false;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to send command'), backgroundColor: AppColors.danger),
                              );
                            }
                          },
                          color: _isLockCommandPending 
                              ? Colors.grey 
                              : (vehicle.isEngineLocked ? AppColors.success : AppColors.danger),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CustomButton(
                          label: 'Sound Alarm',
                          icon: Icons.notifications_active,
                          onPressed: () async {
                            if (vehicle.currentStatus == VehicleStatus.offline) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Tracker is offline. Please wait until it comes online.'), backgroundColor: AppColors.warning),
                              );
                              return;
                            }
                            try {
                              await ref.read(apiClientProvider).post('/vehicles/${vehicle.vehicleId}/alarm', {
                                'state': true // Turn alarm ON
                              });
                              
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Alarm triggered for ${vehicle.vehicleName}'), backgroundColor: AppColors.warning),
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to trigger alarm'), backgroundColor: AppColors.danger),
                              );
                            }
                          },
                          color: AppColors.warning,
                        ),
                      ),
                    ] else ...[
                      Expanded(
                        child: CustomButton(
                          label: 'Driver Auth',
                          isOutlined: true,
                          icon: Icons.fingerprint,
                          onPressed: () {
                            if (vehicle.currentStatus == VehicleStatus.offline) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Tracker is offline. Cannot manage fingerprints right now.'), backgroundColor: AppColors.warning),
                              );
                              return;
                            }
                            Navigator.pushNamed(
                              context, 
                              '/driver-auth',
                              arguments: vehicle,
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
                if (user.role == UserRole.owner || user.role == UserRole.manager) ...[
                  const SizedBox(height: 16),
                  CustomButton(
                    label: 'Manage Fingerprints',
                    icon: Icons.fingerprint,
                    isOutlined: true,
                    onPressed: () {
                      if (vehicle.currentStatus == VehicleStatus.offline) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Tracker is offline. Cannot manage fingerprints right now.'), backgroundColor: AppColors.warning),
                        );
                        return;
                      }
                      Navigator.pushNamed(
                        context, 
                        '/driver-auth',
                        arguments: vehicle,
                      );
                    },
                  ),
                ],
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
