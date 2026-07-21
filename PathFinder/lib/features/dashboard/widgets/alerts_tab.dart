import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/enums/alert_type.dart';
import '../../../shared/widgets/alert_card.dart';

class AlertsTab extends ConsumerStatefulWidget {
  const AlertsTab({super.key});

  @override
  ConsumerState<AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends ConsumerState<AlertsTab> {
  String _selectedFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();
    
    final alertsAsync = ref.watch(alertsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return alertsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
      data: (alerts) {
        final unreadCount = alerts.where((a) => !a.isRead).length;

        // Filter logic
        final filteredAlerts = alerts.where((alert) {
          if (_selectedFilter == 'All') return true;
          if (_selectedFilter == 'Unread') return !alert.isRead;
          // You can add more filters here based on AlertType if needed
          return true;
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
                      'Alerts & Events',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                      ),
                    ),
                    if (unreadCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.danger.withOpacity(0.5)),
                        ),
                        child: Text(
                          '$unreadCount Unread',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Filters
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  children: [
                    _buildFilterChip('All', isDark),
                    const SizedBox(width: 8),
                    _buildFilterChip('Unread', isDark),
                    const SizedBox(width: 8),
                    _buildFilterChip('Security', isDark),
                    const SizedBox(width: 8),
                    _buildFilterChip('Violations', isDark),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),

              // Alerts List
              Expanded(
                child: filteredAlerts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.notifications_off_outlined, size: 64, color: isDark ? AppColors.dividerDark : AppColors.dividerLight),
                            const SizedBox(height: 16),
                            Text(
                              'No alerts found',
                              style: TextStyle(
                                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                        itemCount: filteredAlerts.length,
                        itemBuilder: (context, index) {
                          final alert = filteredAlerts[index];
                          return GestureDetector(
                            onTap: () {
                              if (!alert.isRead) {
                                ref.read(alertsProvider.notifier).markAsRead(alert.alertId);
                              }
                            },
                            child: AlertCard(
                              alert: alert,
                              userRole: user.role,
                              onActionPressed: () {
                                // Action handling goes here
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Action initiated for ${alert.alertType.displayName}')),
                                );
                              },
                              onDismissed: () {
                                ref.read(alertsProvider.notifier).deleteAlert(alert.alertId);
                              },
                            ),
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

  Widget _buildFilterChip(String label, bool isDark) {
    final isSelected = _selectedFilter == label;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected 
              ? AppColors.secondary 
              : (isDark ? AppColors.surfaceDark : AppColors.surfaceLight),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected 
                ? AppColors.secondary 
                : (isDark ? AppColors.dividerDark : AppColors.dividerLight),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected 
                ? Colors.white 
                : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
          ),
        ),
      ),
    );
  }
}
