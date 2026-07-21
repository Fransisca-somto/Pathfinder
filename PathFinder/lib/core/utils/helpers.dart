import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

class Helpers {
  static String formatDateTime(DateTime dateTime) {
    return DateFormat('MMM d, yyyy - h:mm a').format(dateTime);
  }

  static String formatTimeFromNow(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }

  static String formatSpeed(double speed) {
    return '${speed.toStringAsFixed(1)} km/h';
  }

  static String formatDistance(double distance) {
    return '${distance.toStringAsFixed(1)} km';
  }

  static String getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }
}
