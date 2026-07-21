import 'package:flutter/material.dart';
import '../../core/models/vehicle_model.dart';
import '../../core/enums/vehicle_status.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/helpers.dart';

class VehicleCard extends StatelessWidget {
  final VehicleModel vehicle;
  final VoidCallback onTap;
  final String? heroTag;

  const VehicleCard({
    super.key,
    required this.vehicle,
    required this.onTap,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
          ),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heroTag != null
                    ? Hero(
                        tag: heroTag!,
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
                      )
                    : Container(
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
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vehicle.vehicleName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (vehicle.assignedDrivers.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Icon(Icons.person, size: 14, color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  vehicle.assignedDrivers.join(', '),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          Text(
                            vehicle.plateNumber,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            vehicle.isEngineLocked ? Icons.lock : Icons.power_settings_new,
                            size: 14,
                            color: vehicle.isEngineLocked ? AppColors.danger : AppColors.success,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            vehicle.isEngineLocked ? 'Engine Locked' : 'Engine Running',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: vehicle.isEngineLocked ? AppColors.danger : AppColors.success,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: vehicle.currentStatus.color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: vehicle.currentStatus.color.withOpacity(0.5)),
                  ),
                  child: Text(
                    vehicle.currentStatus.displayName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: vehicle.currentStatus.color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: isDark ? AppColors.dividerDark : AppColors.dividerLight),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.speed, size: 16, color: AppColors.secondary),
                    const SizedBox(width: 4),
                    Text(
                      Helpers.formatSpeed(vehicle.currentSpeed),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Icon(Icons.location_on, size: 16, color: AppColors.secondary),
                    const SizedBox(width: 4),
                    Text(
                      vehicle.lastKnownLocation,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                      ),
                    ),
                  ],
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
