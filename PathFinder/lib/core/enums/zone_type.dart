import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

enum ZoneType { safe, unsafe }
enum ShapeType { circle, polygon }

extension ZoneTypeExtension on ZoneType {
  String get displayName {
    switch (this) {
      case ZoneType.safe: return 'Safe Zone';
      case ZoneType.unsafe: return 'Unsafe Zone';
    }
  }

  Color get color {
    switch (this) {
      case ZoneType.safe: return AppColors.success;
      case ZoneType.unsafe: return AppColors.danger;
    }
  }
}
