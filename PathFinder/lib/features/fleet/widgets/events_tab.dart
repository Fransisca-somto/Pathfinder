import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/vehicle_model.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/enums/alert_type.dart';
import 'package:intl/intl.dart';

class EventsTab extends ConsumerWidget {
  final VehicleModel vehicle;
  final bool isDark;

  const EventsTab({
    super.key,
    required this.vehicle,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsState = ref.watch(alertsProvider);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Event Timeline',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: alertsState.when(
              data: (alerts) {
                // Filter alerts for this specific vehicle and sort newest first
                final vehicleAlerts = alerts.where((a) => a.vehicleId == vehicle.vehicleId).toList()
                  ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

                if (vehicleAlerts.isEmpty) {
                  return Center(
                    child: Text(
                      'No events recorded yet.',
                      style: TextStyle(
                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: vehicleAlerts.length,
                  itemBuilder: (context, index) {
                    final event = vehicleAlerts[index];
                    
                    final timeFormat = DateFormat('d/M HH:mm');
                    final timeStr = timeFormat.format(event.timestamp);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border(
                          left: BorderSide(
                            color: event.alertType.color,
                            width: 4,
                          ),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: event.alertType.color.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                event.alertType.icon,
                                color: event.alertType.color,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    event.alertType.displayName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    event.message,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    timeStr,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? AppColors.textSecondaryDark.withOpacity(0.5) : AppColors.textSecondaryLight.withOpacity(0.5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(
                child: Text(
                  'Failed to load events',
                  style: TextStyle(color: AppColors.danger),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
