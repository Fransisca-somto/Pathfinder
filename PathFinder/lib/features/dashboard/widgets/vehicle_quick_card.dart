import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/vehicle_model.dart';
import '../../../core/enums/vehicle_status.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/services/api_client.dart';
import '../../../shared/widgets/custom_button.dart';

class VehicleQuickCard extends ConsumerWidget {
  final VehicleModel vehicle;
  final VoidCallback onClose;

  const VehicleQuickCard({
    super.key,
    required this.vehicle,
    required this.onClose,
  });

  void _showEngineControl(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EngineControlSheet(vehicle: vehicle),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final role = ref.watch(authServiceProvider).currentUserRole;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.5 : 0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: vehicle.currentStatus.color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  vehicle.vehicleType == 'Car' ? Icons.directions_car : Icons.local_shipping,
                  color: vehicle.currentStatus.color,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicle.vehicleName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      vehicle.currentStatus.displayName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: vehicle.currentStatus.color,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Telemetry Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _TelemetryItem(
                icon: Icons.speed,
                label: 'Speed',
                value: '${vehicle.currentSpeed.toStringAsFixed(0)} km/h',
                isDark: isDark,
              ),
              _TelemetryItem(
                icon: Icons.power,
                label: 'Ignition',
                value: vehicle.engineRunning ? 'ON' : 'OFF',
                isDark: isDark,
              ),
              _TelemetryItem(
                icon: Icons.battery_charging_full,
                label: 'Battery',
                value: '${vehicle.batteryVoltage.toStringAsFixed(1)}V (${vehicle.batteryPercentage}%)',
                isDark: isDark,
              ),
              _TelemetryItem(
                icon: Icons.person,
                label: 'Driver',
                value: vehicle.assignedDrivers.isNotEmpty ? 'Assigned' : 'None',
                isDark: isDark,
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Actions
          Row(
            children: [
              Expanded(
                child: CustomButton(
                  label: 'Details',
                  icon: Icons.info_outline,
                  isOutlined: true,
                  onPressed: () {
                    Navigator.pushNamed(context, AppRoutes.vehicleDetail, arguments: vehicle);
                  },
                ),
              ),
              if (role == UserRole.owner || role == UserRole.manager) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: CustomButton(
                    label: 'Alarm',
                    icon: Icons.notifications_active,
                    color: AppColors.warning,
                    onPressed: () async {
                      if (vehicle.currentStatus == VehicleStatus.offline) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Tracker is offline. Please wait until it comes online.'), backgroundColor: AppColors.warning),
                        );
                        return;
                      }
                      try {
                        await ref.read(apiClientProvider).post('/vehicles/${vehicle.vehicleId}/alarm', {
                          'state': true
                        });
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Alarm triggered for ${vehicle.vehicleName}'), backgroundColor: AppColors.warning),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to trigger alarm'), backgroundColor: AppColors.danger),
                          );
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CustomButton(
                    label: 'Engine',
                    icon: Icons.power_settings_new,
                    color: AppColors.danger,
                    onPressed: () {
                      if (vehicle.currentStatus == VehicleStatus.offline) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Tracker is offline. Please wait until it comes online.'), backgroundColor: AppColors.warning),
                        );
                        return;
                      }
                      _showEngineControl(context);
                    },
                  ),
                ),
              ]
            ],
          ),
        ],
      ),
    );
  }
}

class _TelemetryItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;

  const _TelemetryItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
          ),
        ),
      ],
    );
  }
}

class _EngineControlSheet extends StatefulWidget {
  final VehicleModel vehicle;
  
  const _EngineControlSheet({required this.vehicle});

  @override
  State<_EngineControlSheet> createState() => _EngineControlSheetState();
}

class _EngineControlSheetState extends State<_EngineControlSheet> {
  bool _isLoading = false;
  bool _stepTwo = false;

  void _handleCutOff() async {
    if (!_stepTwo) {
      setState(() => _stepTwo = true);
      return;
    }

    setState(() => _isLoading = true);
    // Simulate MQTT relay cut-off command
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    
    setState(() => _isLoading = false);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Engine cut-off command sent successfully.'), backgroundColor: AppColors.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 64, color: AppColors.danger),
            const SizedBox(height: 16),
            Text(
              'Emergency Engine Cut-Off',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _stepTwo
                  ? 'WARNING: This action will disable the starter relay for ${widget.vehicle.vehicleName}. The vehicle will not be able to restart until you manually enable it. Are you absolutely sure?'
                  : 'You are about to disable the engine starter for ${widget.vehicle.vehicleName}. This should only be used in emergencies (e.g., theft).',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
              ),
            ),
            const SizedBox(height: 32),
            CustomButton(
              label: _stepTwo ? 'CONFIRM DISABLE ENGINE' : 'Disable Starter',
              color: AppColors.danger,
              isLoading: _isLoading,
              onPressed: _handleCutOff,
            ),
            const SizedBox(height: 16),
            CustomButton(
              label: 'Cancel',
              isOutlined: true,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}
