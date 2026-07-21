import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/routes/app_routes.dart';

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();

    final themeMode = ref.watch(themeModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Settings',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: AppColors.secondary),
                  onPressed: () {
                    Navigator.pushNamed(context, AppRoutes.editProfile);
                  },
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Profile Avatar & Info
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                    backgroundImage: NetworkImage('https://ui-avatars.com/api/?name=${user.fullName}&background=random'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    user.fullName,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user?.email ?? 'No email provided',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      user?.role.name.toUpperCase() ?? 'UNKNOWN',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),

            // Settings List
            Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? AppColors.dividerDark : AppColors.dividerLight),
              ),
              child: Column(
                children: [
                  _buildListTile(
                    context,
                    icon: Icons.dark_mode,
                    title: 'Dark Mode',
                    trailing: Switch(
                      value: themeMode == ThemeMode.dark || (themeMode == ThemeMode.system && isDark),
                      activeColor: AppColors.secondary,
                      onChanged: (value) {
                        ref.read(themeModeProvider.notifier).setTheme(value ? ThemeMode.dark : ThemeMode.light);
                      },
                    ),
                    isDark: isDark,
                  ),
                  Divider(height: 1, color: isDark ? AppColors.dividerDark : AppColors.dividerLight),
                  _buildListTile(
                    context,
                    icon: Icons.notifications,
                    title: 'Push Notifications',
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.pushNamed(context, AppRoutes.pushNotifications);
                    },
                    isDark: isDark,
                  ),
                  if (user.role == UserRole.owner || user.role == UserRole.manager) ...[
                    Divider(height: 1, color: isDark ? AppColors.dividerDark : AppColors.dividerLight),
                    _buildListTile(
                      context,
                      icon: Icons.map,
                      title: 'Zone Management',
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => Navigator.pushNamed(context, AppRoutes.zoneManagement),
                      isDark: isDark,
                    ),
                    Divider(height: 1, color: isDark ? AppColors.dividerDark : AppColors.dividerLight),
                    _buildListTile(
                      context,
                      icon: Icons.history,
                      title: 'Fleet Event Log',
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => Navigator.pushNamed(context, AppRoutes.fleetEventLog),
                      isDark: isDark,
                    ),
                    Divider(height: 1, color: isDark ? AppColors.dividerDark : AppColors.dividerLight),
                    _buildListTile(
                      context,
                      icon: Icons.group,
                      title: 'User Management',
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => Navigator.pushNamed(context, AppRoutes.userManagement),
                      isDark: isDark,
                    ),
                  ],
                  Divider(height: 1, color: isDark ? AppColors.dividerDark : AppColors.dividerLight),
                  _buildListTile(
                    context,
                    icon: Icons.security,
                    title: 'Privacy & Security',
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.pushNamed(context, AppRoutes.privacySecurity);
                    },
                    isDark: isDark,
                  ),
                  Divider(height: 1, color: isDark ? AppColors.dividerDark : AppColors.dividerLight),
                  _buildListTile(
                    context,
                    icon: Icons.help_outline,
                    title: 'Help & Support',
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.pushNamed(context, AppRoutes.helpSupport);
                    },
                    isDark: isDark,
                  ),
                  if (user.role == UserRole.owner || user.role == UserRole.manager) ...[
                    Divider(height: 1, color: isDark ? AppColors.dividerDark : AppColors.dividerLight),
                    _buildListTile(
                      context,
                      icon: Icons.speed,
                      title: 'System Performance',
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => Navigator.pushNamed(context, AppRoutes.systemPerformance),
                      isDark: isDark,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Logout Button
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () {
                  // Perform logout (just navigate to login screen for mock)
                  Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (route) => false);
                },
                icon: const Icon(Icons.logout, color: AppColors.danger),
                label: const Text(
                  'Log Out',
                  style: TextStyle(
                    color: AppColors.danger,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: AppColors.danger.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListTile(BuildContext context, {
    required IconData icon,
    required String title,
    required Widget trailing,
    VoidCallback? onTap,
    required bool isDark,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
        ),
      ),
      trailing: trailing,
    );
  }
}
