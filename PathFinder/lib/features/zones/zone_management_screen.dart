import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/enums/zone_type.dart';
import '../../../core/routes/app_routes.dart';

class ZoneManagementScreen extends ConsumerStatefulWidget {
  const ZoneManagementScreen({super.key});

  @override
  ConsumerState<ZoneManagementScreen> createState() => _ZoneManagementScreenState();
}

class _ZoneManagementScreenState extends ConsumerState<ZoneManagementScreen> {
  @override
  Widget build(BuildContext context) {
    final zonesAsync = ref.watch(zonesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Zone Management'),
        backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        foregroundColor: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
        iconTheme: IconThemeData(color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
        elevation: 0,
      ),
      body: zonesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (zones) {
          if (zones.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.map_outlined, size: 64, color: isDark ? AppColors.dividerDark : AppColors.dividerLight),
                  const SizedBox(height: 16),
                  Text(
                    'No zones configured yet.',
                    style: TextStyle(color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
                  )
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(24.0),
            itemCount: zones.length,
            itemBuilder: (context, index) {
              final zone = zones[index];
              return InkWell(
                onTap: () {
                  Navigator.pushNamed(context, AppRoutes.drawZone, arguments: zone);
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16.0),
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isDark ? AppColors.dividerDark : AppColors.dividerLight),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: zone.zoneType.color.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          zone.zoneType == ZoneType.safe ? Icons.verified_user : Icons.warning_amber_rounded,
                          color: zone.zoneType.color,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              zone.zoneName,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Type: ${zone.zoneType.displayName} • Radius: ${(zone.radiusMeters / 1000).toStringAsFixed(1)}km',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, color: AppColors.secondary),
                            onPressed: () {
                              Navigator.pushNamed(context, AppRoutes.drawZone, arguments: zone);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('${zone.zoneName} deleted!')),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        onPressed: () {
          Navigator.pushNamed(context, AppRoutes.drawZone);
        },
        icon: const Icon(Icons.add_location_alt, color: Colors.white),
        label: const Text('Draw Zone', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
