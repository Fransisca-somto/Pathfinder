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
  temperature,
  enrollProgress,
  enrollSuccess,
  enrollFailed,
  authDenied,
  sensorFault,
  danger,
  call,
  authSilent,
  zoneEnter,
  commandAck,
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
      case AlertType.enrollProgress: return 'Enrollment Progress';
      case AlertType.enrollSuccess: return 'Enrollment Success';
      case AlertType.enrollFailed: return 'Enrollment Failed';
      case AlertType.authDenied: return 'Auth Denied';
      case AlertType.sensorFault: return 'Sensor Fault';
      case AlertType.danger: return 'Danger';
      case AlertType.call: return 'Voice Call';
      case AlertType.authSilent: return 'Silent Auth';
      case AlertType.zoneEnter: return 'Zone Enter';
      case AlertType.commandAck: return 'Command Ack';
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
      case AlertType.authDenied:
      case AlertType.danger:
      case AlertType.sensorFault:
        return AppColors.danger;
      case AlertType.idle:
      case AlertType.maintenance:
      case AlertType.smsFallback:
        return AppColors.warning;
      case AlertType.offline:
      case AlertType.system:
      case AlertType.enrollProgress:
      case AlertType.authSilent:
        return Colors.grey;
      case AlertType.call:
      case AlertType.zoneEnter:
      case AlertType.commandAck:
        return AppColors.info;
      case AlertType.authSuccess:
      case AlertType.enrollSuccess:
        return AppColors.success;
      case AlertType.enrollFailed:
        return AppColors.danger;
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
      case AlertType.enrollProgress: return Icons.fingerprint;
      case AlertType.enrollSuccess: return Icons.check_circle;
      case AlertType.enrollFailed: return Icons.cancel;
      case AlertType.authDenied: return Icons.block;
      case AlertType.sensorFault: return Icons.warning;
      case AlertType.danger: return Icons.gavel; // Or something
      case AlertType.call: return Icons.phone;
      case AlertType.authSilent: return Icons.fingerprint;
      case AlertType.zoneEnter: return Icons.login;
      case AlertType.commandAck: return Icons.check;
    }
  }
}
