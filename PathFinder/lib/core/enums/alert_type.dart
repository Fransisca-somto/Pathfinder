import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

enum AlertType {
  zoneExit,
  speed,
  idle,
  maintenance,
  authFailure,
  engineLock,
  offline,
  smsFallback,
  system,
  panic,
  crash,
  authSuccess,
  theft,
  temperature
}

extension AlertTypeExtension on AlertType {
  String get displayName {
    switch (this) {
      case AlertType.zoneExit: return 'Zone Exit';
      case AlertType.speed: return 'Overspeeding';
      case AlertType.idle: return 'Idle Too Long';
      case AlertType.maintenance: return 'Maintenance Due';
      case AlertType.authFailure: return 'Auth Failed';
      case AlertType.engineLock: return 'Engine Locked';
      case AlertType.offline: return 'Vehicle Offline';
      case AlertType.smsFallback: return 'SMS Fallback';
      case AlertType.system: return 'System';
      case AlertType.panic: return 'Emergency SOS';
      case AlertType.crash: return 'Crash Detected!';
      case AlertType.authSuccess: return 'Auth Success';
      case AlertType.theft: return 'Theft Attempt';
      case AlertType.temperature: return 'Engine Temp Alert';
    }
  }

  Color get color {
    switch (this) {
      case AlertType.zoneExit:
      case AlertType.speed:
      case AlertType.authFailure:
      case AlertType.engineLock:
      case AlertType.panic:
      case AlertType.crash:
      case AlertType.theft:
      case AlertType.temperature:
        return AppColors.danger;
      case AlertType.idle:
      case AlertType.maintenance:
      case AlertType.smsFallback:
        return AppColors.warning;
      case AlertType.offline:
      case AlertType.system:
        return Colors.grey;
      case AlertType.authSuccess:
        return AppColors.success;
    }
  }

  IconData get icon {
    switch (this) {
      case AlertType.zoneExit: return Icons.logout;
      case AlertType.speed: return Icons.speed;
      case AlertType.idle: return Icons.timer;
      case AlertType.maintenance: return Icons.build;
      case AlertType.authFailure: return Icons.fingerprint;
      case AlertType.engineLock: return Icons.lock;
      case AlertType.offline: return Icons.signal_wifi_off;
      case AlertType.smsFallback: return Icons.sms;
      case AlertType.system: return Icons.info;
      case AlertType.panic: return Icons.sos;
      case AlertType.crash: return Icons.car_crash;
      case AlertType.authSuccess: return Icons.verified_user;
      case AlertType.theft: return Icons.security;
      case AlertType.temperature: return Icons.thermostat;
    }
  }
}
