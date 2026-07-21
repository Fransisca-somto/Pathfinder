import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/models/user_model.dart';
import '../../../core/utils/dummy_data.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/role_badge.dart';

class UserManagementScreen extends ConsumerStatefulWidget {
  const UserManagementScreen({super.key});

  @override
  ConsumerState<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends ConsumerState<UserManagementScreen> {
  // In a real app, we'd fetch this from a provider/backend.
  late List<UserModel> _users;

  @override
  void initState() {
    super.initState();
    // Create a mutable copy of the dummy data for UI demonstration
    _users = List.from(DummyData.users);
  }

  void _showRoleDialog(UserModel user) {
    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        UserRole selectedRole = user.role;

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              title: Text('Edit Role: ${user.fullName}', style: TextStyle(color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: UserRole.values.map((role) {
                  return RadioListTile<UserRole>(
                    title: Text(role.name.toUpperCase()),
                    value: role,
                    groupValue: selectedRole,
                    onChanged: (value) {
                      if (value != null) setState(() => selectedRole = value);
                    },
                  );
                }).toList(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Update user locally
                    final index = _users.indexWhere((u) => u.userId == user.userId);
                    if (index != -1) {
                      this.setState(() {
                        _users[index] = _users[index].copyWith(role: selectedRole);
                      });
                    }
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User role updated.')));
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _inviteUserDialog() {
    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          title: Text('Invite New User', style: TextStyle(color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: InputDecoration(
                  labelText: 'Email Address',
                  prefixIcon: const Icon(Icons.email),
                  filled: true,
                  fillColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<UserRole>(
                decoration: InputDecoration(
                  labelText: 'Role',
                  filled: true,
                  fillColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                value: UserRole.driver,
                items: UserRole.values.map((role) {
                  return DropdownMenuItem(
                    value: role,
                    child: Text(role.name.toUpperCase()),
                  );
                }).toList(),
                onChanged: (val) {},
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            CustomButton(
              label: 'Send Invite',
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invitation sent successfully.')));
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
        backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        foregroundColor: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _inviteUserDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('Invite User'),
        backgroundColor: AppColors.primary,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: _users.length,
        itemBuilder: (context, index) {
          final user = _users[index];
          
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withOpacity(0.2),
                child: Text(
                  user.fullName.substring(0, 1).toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
              ),
              title: Text(
                user.fullName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    user.email,
                    style: TextStyle(
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 8),
                  RoleBadge(role: user.role),
                ],
              ),
              trailing: PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
                onSelected: (value) {
                  if (value == 'edit_role') {
                    _showRoleDialog(user);
                  } else if (value == 'assign_vehicle' && user.role == UserRole.driver) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Assign Vehicle dialog coming soon.')));
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit_role',
                    child: Text('Edit Role'),
                  ),
                  if (user.role == UserRole.driver)
                    const PopupMenuItem(
                      value: 'assign_vehicle',
                      child: Text('Assign Vehicle'),
                    ),
                  const PopupMenuItem(
                    value: 'remove_user',
                    child: Text('Remove User', style: TextStyle(color: AppColors.danger)),
                  ),
                ],
              ),
              isThreeLine: true,
            ),
          );
        },
      ),
    );
  }
}
