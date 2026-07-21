import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/enums/user_role.dart';
import '../../../shared/widgets/vehicle_card.dart';
import '../../../shared/widgets/custom_textfield.dart';

class FleetTab extends ConsumerStatefulWidget {
  const FleetTab({super.key});

  @override
  ConsumerState<FleetTab> createState() => _FleetTabState();
}

class _FleetTabState extends ConsumerState<FleetTab> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final vehiclesAsync = ref.watch(vehiclesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return vehiclesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
      data: (vehicles) {
        if (user == null) return const SizedBox.shrink();

        final filteredVehicles = vehicles.where((v) {
          return v.vehicleName.toLowerCase().contains(_searchQuery) ||
                 v.plateNumber.toLowerCase().contains(_searchQuery);
        }).toList();

        return SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Fleet Management',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                      ),
                    ),
                    if (user.role == UserRole.owner || user.role == UserRole.manager)
                      IconButton(
                        onPressed: () => Navigator.pushNamed(context, AppRoutes.addVehicle),
                        icon: const Icon(Icons.add_circle, color: AppColors.secondary, size: 32),
                      ),
                  ],
                ),
              ),

              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: CustomTextField(
                  label: '',
                  hint: 'Search by name or plate...',
                  controller: _searchController,
                  prefixIcon: Icons.search,
                ),
              ),
              const SizedBox(height: 16),

              // Vehicle List
              Expanded(
                child: filteredVehicles.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.directions_car_outlined, size: 64, color: isDark ? AppColors.dividerDark : AppColors.dividerLight),
                            const SizedBox(height: 16),
                            Text(
                              'No vehicles found',
                              style: TextStyle(
                                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                        itemCount: filteredVehicles.length,
                        itemBuilder: (context, index) {
                          final vehicle = filteredVehicles[index];
                          return VehicleCard(
                            vehicle: vehicle,
                            heroTag: 'vehicle_icon_${vehicle.vehicleId}',
                            onTap: () {
                              Navigator.pushNamed(
                                context,
                                AppRoutes.vehicleDetail,
                                arguments: vehicle,
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
