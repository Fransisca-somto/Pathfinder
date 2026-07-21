import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/enums/vehicle_status.dart';
import '../../../shared/widgets/role_badge.dart';
import '../../../shared/widgets/stats_card.dart';
import '../../../shared/widgets/vehicle_card.dart';

import '../../../core/enums/user_role.dart';

class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();
    
    final vehiclesAsync = ref.watch(vehiclesProvider);
    final alertsAsync = ref.watch(alertsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return vehiclesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
      data: (vehicles) {
        final alerts = alertsAsync.value ?? [];

        // Calculate Stats
        final activeVehicles = vehicles.where((v) => v.currentStatus == VehicleStatus.moving).length;
        final idleVehicles = vehicles.where((v) => v.currentStatus == VehicleStatus.parked || v.currentStatus == VehicleStatus.offline).length;
        final unreadAlerts = alerts.where((a) => !a.isRead).length;

        return SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header section
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Good Morning,',
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
                      
                      // Stats Grid
                      Text(
                        'Fleet Overview',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                        ),
                      ),
                      const SizedBox(height: 16),
                      GridView.count(
                        crossAxisCount: 2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        childAspectRatio: 2.2,
                        children: [
                          StatsCard(
                            title: 'Total Vehicles',
                            value: vehicles.length.toString(),
                            icon: Icons.directions_car,
                            color: AppColors.primary,
                          ),
                          StatsCard(
                            title: 'Active Now',
                            value: activeVehicles.toString(),
                            icon: Icons.check_circle,
                            color: AppColors.success,
                          ),
                          StatsCard(
                            title: 'Idle / Offline',
                            value: idleVehicles.toString(),
                            icon: Icons.timer,
                            color: AppColors.warning,
                          ),
                          StatsCard(
                            title: 'Unread Alerts',
                            value: unreadAlerts.toString(),
                            icon: Icons.notifications_active,
                            color: AppColors.danger,
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 32),
                      
                      // Recent Activity
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Recent Activity',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                            ),
                          ),
                          if (user.role != UserRole.driver)
                            TextButton(
                              onPressed: () {
                                ref.read(dashboardIndexProvider.notifier).setIndex(3); // Fleet Tab Index
                              },
                              child: const Text('View All'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              
              // Vehicles List
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final vehicle = vehicles[index];
                      return VehicleCard(
                        vehicle: vehicle,
                        heroTag: 'home_vehicle_icon_${vehicle.vehicleId}',
                        onTap: () {
                          Navigator.pushNamed(
                            context,
                            '/vehicle-detail',
                            arguments: vehicle,
                          );
                        },
                      );
                    },
                    childCount: vehicles.length,
                  ),
                ),
              ),
              
              const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
            ],
          ),
        );
      },
    );
  }
}
