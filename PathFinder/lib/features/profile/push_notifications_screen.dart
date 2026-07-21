import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class PushNotificationsScreen extends StatefulWidget {
  const PushNotificationsScreen({super.key});

  @override
  State<PushNotificationsScreen> createState() => _PushNotificationsScreenState();
}

class _PushNotificationsScreenState extends State<PushNotificationsScreen> {
  bool _securityAlerts = true;
  bool _geofenceViolations = true;
  bool _systemUpdates = false;
  bool _dailyReports = true;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Push Notifications'),
        backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        foregroundColor: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
        iconTheme: IconThemeData(color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          _buildSectionHeader('Critical Alerts', isDark),
          _buildSwitchTile(
            title: 'Security Alerts',
            subtitle: 'Engine starts without authorization, tampering detected.',
            value: _securityAlerts,
            onChanged: (val) => setState(() => _securityAlerts = val),
            isDark: isDark,
          ),
          _buildSwitchTile(
            title: 'Geofence Violations',
            subtitle: 'Vehicle exits or enters restricted zones.',
            value: _geofenceViolations,
            onChanged: (val) => setState(() => _geofenceViolations = val),
            isDark: isDark,
          ),
          
          const SizedBox(height: 32),
          _buildSectionHeader('General Notifications', isDark),
          _buildSwitchTile(
            title: 'Daily Reports',
            subtitle: 'Receive a summary of fleet activity every evening.',
            value: _dailyReports,
            onChanged: (val) => setState(() => _dailyReports = val),
            isDark: isDark,
          ),
          _buildSwitchTile(
            title: 'System Updates',
            subtitle: 'New features and maintenance announcements.',
            value: _systemUpdates,
            onChanged: (val) => setState(() => _systemUpdates = val),
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isDark,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? AppColors.dividerDark : AppColors.dividerLight),
      ),
      child: SwitchListTile(
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
            ),
          ),
        ),
        value: value,
        activeColor: AppColors.secondary,
        onChanged: onChanged,
      ),
    );
  }
}
