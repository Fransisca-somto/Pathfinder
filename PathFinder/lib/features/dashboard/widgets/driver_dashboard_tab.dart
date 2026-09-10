import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/enums/vehicle_status.dart';
import '../../../shared/widgets/role_badge.dart';

class DriverDashboardTab extends ConsumerWidget {
  const DriverDashboardTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();
    final vehiclesAsync = ref.watch(vehiclesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return vehiclesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
      data: (vehicles) {
        // Find assigned vehicle (dummy logic: just grab the first one for the mock)
        final assignedVehicle = vehicles.isNotEmpty ? vehicles.first : null;

        // Dynamic greeting
        final hour = DateTime.now().hour;
        String greeting = 'Good Evening,';
        if (hour < 12) {
          greeting = 'Good Morning,';
        } else if (hour < 17) {
          greeting = 'Good Afternoon,';
        }

        return SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                greeting,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                user.fullName,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                                ),
                              ),
                            ],
                          ),
                          RoleBadge(role: user.role),
                        ],
                      ),
                      const SizedBox(height: 32),

                      if (assignedVehicle == null)
                        const Center(child: Text('No vehicle assigned.'))
                      else ...[
                        // Large Status Card
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                assignedVehicle.currentStatus.color,
                                assignedVehicle.currentStatus.color.withOpacity(0.7),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: assignedVehicle.currentStatus.color.withOpacity(0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    assignedVehicle.vehicleName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      assignedVehicle.plateNumber,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildStatusInfo('Status', assignedVehicle.currentStatus.displayName),
                                  _buildStatusInfo('Speed', '${assignedVehicle.currentSpeed.toStringAsFixed(0)} km/h'),
                                  _buildStatusInfo('Engine', assignedVehicle.isEngineLocked ? 'LOCKED' : 'READY'),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Fingerprint Status
                        _buildSectionCard(
                          title: 'Authentication Status',
                          icon: Icons.fingerprint,
                          isDark: isDark,
                          child: Row(
                            children: [
                              Icon(Icons.check_circle, color: AppColors.success, size: 32),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Identity Verified',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                                      ),
                                    ),
                                    Text(
                                      'You are authorized to operate this vehicle.',
                                      style: TextStyle(
                                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Current Trip Summary
                        _buildSectionCard(
                          title: 'Current Trip',
                          icon: Icons.route,
                          isDark: isDark,
                          child: Column(
                            children: [
                              _buildTripRow('Start Time', '08:30 AM', Icons.access_time, isDark),
                              const Divider(),
                              _buildTripRow('Distance', '45.2 km', Icons.straighten, isDark),
                              const Divider(),
                              _buildTripRow('Duration', '1h 15m', Icons.timer, isDark),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),
                        
                        // Driving Alerts
                        _buildSectionCard(
                          title: 'Recent Driving Alerts',
                          icon: Icons.warning_amber,
                          isDark: isDark,
                          child: Column(
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.warning.withOpacity(0.1),
                                  child: Icon(Icons.speed, color: AppColors.warning),
                                ),
                                title: Text('Speed Limit Exceeded', style: TextStyle(color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight)),
                                subtitle: Text('10:45 AM • Zone: Downtown', style: TextStyle(color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
                              ),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.danger.withOpacity(0.1),
                                  child: Icon(Icons.car_crash, color: AppColors.danger),
                                ),
                                title: Text('Harsh Braking', style: TextStyle(color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight)),
                                subtitle: Text('09:12 AM • Zone: Highway 1', style: TextStyle(color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusInfo(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionCard({required String title, required IconData icon, required bool isDark, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildTripRow(String label, String value, IconData icon, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                ),
              ),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            ),
          ),
        ],
      ),
    );
  }
}
