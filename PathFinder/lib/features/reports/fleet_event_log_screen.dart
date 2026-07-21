import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/enums/alert_type.dart';

class FleetEventLogScreen extends ConsumerStatefulWidget {
  const FleetEventLogScreen({super.key});

  @override
  ConsumerState<FleetEventLogScreen> createState() => _FleetEventLogScreenState();
}

class _FleetEventLogScreenState extends ConsumerState<FleetEventLogScreen> {
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final alertsAsync = ref.watch(alertsProvider);
    final allAlerts = alertsAsync.value ?? [];

    // Sort by timestamp descending
    final sortedAlerts = List.of(allAlerts)..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Filter
    final displayAlerts = sortedAlerts.where((alert) {
      if (_filter == 'All') return true;
      if (_filter == 'Critical') return alert.alertType.color == AppColors.danger;
      if (_filter == 'Warning') return alert.alertType.color == AppColors.warning;
      if (_filter == 'Info') return alert.alertType.color != AppColors.danger && alert.alertType.color != AppColors.warning;
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fleet Event Log'),
        backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        foregroundColor: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
        iconTheme: IconThemeData(color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Export CSV',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Exporting event log to CSV...')),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            child: Row(
              children: [
                Text(
                  'Filter by:',
                  style: TextStyle(
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ['All', 'Critical', 'Warning', 'Info'].map((filterStr) {
                        final isSelected = _filter == filterStr;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ChoiceChip(
                            label: Text(filterStr),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) setState(() => _filter = filterStr);
                            },
                            selectedColor: AppColors.secondary.withOpacity(0.2),
                            labelStyle: TextStyle(
                              color: isSelected 
                                  ? AppColors.secondary 
                                  : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // List
          Expanded(
            child: ListView.builder(
              itemCount: displayAlerts.length,
              itemBuilder: (context, index) {
                final alert = displayAlerts[index];
                
                final typeColor = alert.alertType.color;
                final typeIcon = alert.alertType.icon;

                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border(
                      left: BorderSide(
                        color: typeColor,
                        width: 4,
                      ),
                    ),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: typeColor.withOpacity(0.1),
                      child: Icon(typeIcon, color: typeColor),
                    ),
                    title: Text(
                      alert.alertType.displayName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          alert.message,
                          style: TextStyle(
                            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${alert.timestamp.day}/${alert.timestamp.month}/${alert.timestamp.year} ${alert.timestamp.hour.toString().padLeft(2, '0')}:${alert.timestamp.minute.toString().padLeft(2, '0')} • Vehicle ID: ${alert.vehicleId}',
                          style: TextStyle(
                            fontSize: 12,
                            color: (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight).withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
