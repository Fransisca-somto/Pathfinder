import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

enum UserRole { owner, manager, driver }

extension UserRoleExtension on UserRole {
  String get displayName {
    switch (this) {
      case UserRole.owner:
        return 'Owner';
      case UserRole.manager:
        return 'Manager';
      case UserRole.driver:
        return 'Driver';
    }
  }

  Color get color {
    switch (this) {
      case UserRole.owner:
        return AppColors.secondary; // Electric Blue
      case UserRole.manager:
        return AppColors.accent; // Bright Cyan
      case UserRole.driver:
        return AppColors.warning; // Amber
    }
  }

  IconData get icon {
    switch (this) {
      case UserRole.owner:
        return Icons.admin_panel_settings;
      case UserRole.manager:
        return Icons.manage_accounts;
      case UserRole.driver:
        return Icons.directions_car;
    }
  }
}
