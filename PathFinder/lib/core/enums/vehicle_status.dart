import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

enum VehicleStatus { moving, parked, alarm, pendingAuth, offline }

extension VehicleStatusExtension on VehicleStatus {
  String get displayName {
    switch (this) {
      case VehicleStatus.moving:
        return 'Moving';
      case VehicleStatus.parked:
        return 'Parked';
      case VehicleStatus.alarm:
        return 'Alarm';
      case VehicleStatus.pendingAuth:
        return 'Pending Auth';
      case VehicleStatus.offline:
        return 'Offline';
    }
  }

  Color get color {
    switch (this) {
      case VehicleStatus.moving:
        return AppColors.success;
      case VehicleStatus.parked:
        return AppColors.secondary;
      case VehicleStatus.alarm:
      case VehicleStatus.pendingAuth:
        return AppColors.danger;
      case VehicleStatus.offline:
        return Colors.grey;
    }
  }
}
