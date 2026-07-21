import 'package:flutter/material.dart';
import '../../core/models/alert_model.dart';
import '../../core/enums/alert_type.dart';
import '../../core/enums/user_role.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/helpers.dart';
import 'custom_button.dart';

class AlertCard extends StatelessWidget {
  final AlertModel alert;
  final UserRole userRole;
  final VoidCallback onActionPressed;
  final VoidCallback onDismissed;

  const AlertCard({
    super.key,
    required this.alert,
    required this.userRole,
    required this.onActionPressed,
    required this.onDismissed,
  });

  String _getActionLabel() {
    if (userRole == UserRole.driver) {
      if (alert.alertType == AlertType.zoneExit) return 'Authenticate Now';
      if (alert.alertType == AlertType.speed) return 'View on Map';
      return 'Dismiss';
    } else {
      // Owner / Manager Actions
      if (alert.alertType == AlertType.zoneExit) return 'Lock Engine';
      if (alert.alertType == AlertType.speed) return 'View on Map';
      if (alert.alertType == AlertType.authFailure) return 'Override Lock';
      if (alert.alertType == AlertType.engineLock) return 'Unlock Engine';
      if (alert.alertType == AlertType.smsFallback) return 'View Details';
      return 'Dismiss';
    }
  }

  bool _shouldShowAction() {
    if (userRole == UserRole.driver) {
      // Hide auth failures and engine lock alerts for the driver
      if (alert.alertType == AlertType.authFailure || alert.alertType == AlertType.engineLock) {
        return false;
      }
    }
    return alert.requiresAction;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Unread styling logic
    final backgroundColor = alert.isRead
        ? (isDark ? AppColors.surfaceDark : AppColors.surfaceLight)
        : (isDark ? AppColors.secondary.withOpacity(0.1) : AppColors.secondary.withOpacity(0.05));

    return Dismissible(
      key: Key(alert.alertId),
      onDismissed: (direction) => onDismissed(),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: alert.isRead 
                ? (isDark ? AppColors.dividerDark : AppColors.dividerLight)
                : AppColors.secondary.withOpacity(0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: alert.alertType.color.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(alert.alertType.icon, color: alert.alertType.color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alert.alertType.displayName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${alert.vehicleName} • ${Helpers.formatTimeFromNow(alert.timestamp)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!alert.isRead)
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: AppColors.secondary,
                      shape: BoxShape.circle,
                    ),
                  )
              ],
            ),
            const SizedBox(height: 12),
            Text(
              alert.message,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                height: 1.4,
              ),
            ),
            if (_shouldShowAction()) ...[
              const SizedBox(height: 16),
              CustomButton(
                label: _getActionLabel(),
                onPressed: onActionPressed,
                isOutlined: true,
              )
            ]
          ],
        ),
      ),
    );
  }
}
