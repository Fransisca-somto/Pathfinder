import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/enums/user_role.dart';

class RoleBadge extends StatelessWidget {
  final UserRole role;

  const RoleBadge({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: role.color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: role.color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(role.icon, size: 14, color: role.color),
          const SizedBox(width: 4),
          Text(
            role.displayName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: role.color,
            ),
          ),
        ],
      ),
    );
  }
}
