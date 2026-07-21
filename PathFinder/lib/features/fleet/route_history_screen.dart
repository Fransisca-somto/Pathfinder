import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/models/vehicle_model.dart';
import '../../core/providers/app_providers.dart';

class RouteHistoryScreen extends ConsumerWidget {
  final VehicleModel vehicle;

  const RouteHistoryScreen({super.key, required this.vehicle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tripsAsyncValue = ref.watch(tripsProvider(vehicle.vehicleId));

    return Scaffold(
      appBar: AppBar(
        title: Text('${vehicle.plateNumber} History'),
        backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        foregroundColor: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
        iconTheme: IconThemeData(color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
        elevation: 0,
      ),
      body: tripsAsyncValue.when(
        data: (trips) {
          if (trips.isEmpty) {
            return Center(
              child: Text(
                'No trip history found.',
                style: TextStyle(
                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  fontSize: 16,
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(24.0),
            itemCount: trips.length,
            itemBuilder: (context, index) {
              final trip = trips[index];
              
              // Format date nicely
              final isToday = DateTime.now().difference(trip.startTime).inDays == 0;
              final isYesterday = DateTime.now().difference(trip.startTime).inDays == 1;
              
              String datePrefix = '';
              if (isToday) {
                datePrefix = 'Today, ';
              } else if (isYesterday) {
                datePrefix = 'Yesterday, ';
              } else {
                datePrefix = DateFormat('MMM d, ').format(trip.startTime);
              }
              
              final timeStr = DateFormat('hh:mm a').format(trip.startTime);
              final displayDate = '$datePrefix$timeStr';

              return Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isDark ? AppColors.dividerDark : AppColors.dividerLight),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          displayDate,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppColors.textPrimaryDark : AppColors.primary,
                          ),
                        ),
                        if (trip.distanceKm != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.secondary.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${trip.distanceKm!.toStringAsFixed(1)} km',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.secondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            Icon(Icons.trip_origin, size: 16, color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
                            Container(
                              width: 2,
                              height: 30,
                              color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
                            ),
                            const Icon(Icons.location_on, size: 16, color: AppColors.danger),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                trip.startAddress ?? '${trip.startLat.toStringAsFixed(4)}, ${trip.startLng.toStringAsFixed(4)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                trip.endAddress ?? (trip.endTime != null ? '${trip.endLat?.toStringAsFixed(4)}, ${trip.endLng?.toStringAsFixed(4)}' : 'Trip in progress...'),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (trip.durationMins != null) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.timer, size: 16, color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
                          const SizedBox(width: 8),
                          Text(
                            'Trip Duration: ${trip.durationMins} mins',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Text(
            'Failed to load trips\n$err',
            style: const TextStyle(color: AppColors.danger),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
