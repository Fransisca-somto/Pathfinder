import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/models/vehicle_model.dart';
import '../../core/models/fingerprint_profile_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/custom_button.dart';
import '../../core/services/api_client.dart';
import '../../core/enums/alert_type.dart';
import 'package:intl/intl.dart';

class DriverAuthScreen extends ConsumerStatefulWidget {
  final VehicleModel vehicle;

  const DriverAuthScreen({super.key, required this.vehicle});

  @override
  ConsumerState<DriverAuthScreen> createState() => _DriverAuthScreenState();
}

class _DriverAuthScreenState extends ConsumerState<DriverAuthScreen> {
  final ValueNotifier<bool> bypassState = ValueNotifier<bool>(false);

  Future<void> _toggleDriver(int slotId, bool isActive) async {
    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.post(
        '/vehicles/${widget.vehicle.vehicleId}/fingerprints/$slotId/toggle',
        {'isActive': isActive},
      );
      ref.invalidate(fingerprintsProvider(widget.vehicle.vehicleId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to toggle driver: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _showAddDriverDialog() async {
    final nameController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Driver'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Driver Name'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                Navigator.pop(context);
                _enrollDriver(name);
              },
              child: const Text('Add & Enroll'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _enrollDriver(String driverName) async {
    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.post('/vehicles/${widget.vehicle.vehicleId}/fingerprints', {
        'driverName': driverName,
      });
      ref.invalidate(fingerprintsProvider(widget.vehicle.vehicleId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enrollment command sent for $driverName! Place finger on sensor.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add driver: $e')),
        );
      }
    }
  }

  Future<void> _deleteDriver(int slotId) async {
    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.delete('/vehicles/${widget.vehicle.vehicleId}/fingerprints/$slotId');
      ref.invalidate(fingerprintsProvider(widget.vehicle.vehicleId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Driver removed and delete command sent to vehicle.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove driver: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final alertsAsync = ref.watch(alertsProvider);
    final fingerprintsAsync = ref.watch(fingerprintsProvider(widget.vehicle.vehicleId));

    ref.listen(alertsProvider, (previous, next) {
      if (next.hasValue && next.value != null && next.value!.isNotEmpty) {
        final latestAlert = next.value!.first;
        if (latestAlert.alertType == AlertType.system) {
          if (latestAlert.message.contains('Fingerprint enrollment successful') || 
              latestAlert.message.contains('Fingerprint enrollment timeout')) {
            ref.invalidate(fingerprintsProvider(widget.vehicle.vehicleId));
            
            if (latestAlert.message.contains('timeout') && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Enrollment timed out. No finger was detected.'),
                  backgroundColor: AppColors.danger,
                ),
              );
            }
          }
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Authentication'),
        backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        foregroundColor: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
        iconTheme: IconThemeData(color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDriverDialog,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.person_add, color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bypass Switch
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? AppColors.dividerDark : AppColors.dividerLight),
              ),
              child: ValueListenableBuilder<bool>(
                valueListenable: bypassState,
                builder: (context, isBypassed, child) {
                  return SwitchListTile(
                    title: Text(
                      'Deactivate Engine Lock (Bypass)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                      ),
                    ),
                    subtitle: Text(
                      'If enabled, anyone can start the vehicle without a fingerprint.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                      ),
                    ),
                    value: isBypassed,
                    activeColor: AppColors.danger,
                    onChanged: (val) async {
                      try {
                        final apiClient = ref.read(apiClientProvider);
                        await apiClient.post('/vehicles/${widget.vehicle.vehicleId}/auth-bypass', {
                          'state': val
                        });
                        bypassState.value = val;
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(val ? 'Engine lock deactivated!' : 'Engine lock activated!')),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to update bypass state: $e')),
                          );
                        }
                      }
                    },
                  );
                }
              ),
            ),
            const SizedBox(height: 32),

            Text(
              'Authorized Drivers',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
              ),
            ),
            const SizedBox(height: 16),

            fingerprintsAsync.when(
              data: (profiles) {
                if (profiles.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('No drivers enrolled yet. Tap + to add one.'),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: profiles.length,
                  itemBuilder: (context, index) {
                    final profile = profiles[index];
                    final isPending = profile.status == 'pending';

                    return Card(
                      color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primary.withOpacity(0.2),
                          child: const Icon(Icons.person, color: AppColors.primary),
                        ),
                        title: Row(
                          children: [
                            Text(profile.driverName, style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            if (isPending)
                              PendingCountdownBadge(createdAt: profile.createdAt)
                            else
                              Row(
                                children: [
                                  Switch(
                                    value: profile.isActive,
                                    onChanged: (val) => _toggleDriver(profile.slotId, val),
                                    activeColor: AppColors.success,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(profile.isActive ? 'Active' : 'Disabled', 
                                    style: TextStyle(
                                      color: profile.isActive ? AppColors.success : AppColors.danger, 
                                      fontSize: 12, 
                                      fontWeight: FontWeight.bold
                                    )
                                  ),
                                ]
                              ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: AppColors.danger),
                          onPressed: () => _deleteDriver(profile.slotId),
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const CircularProgressIndicator(),
              error: (err, stack) => Text('Error: $err'),
            ),

            const SizedBox(height: 32),
            Text(
              'Authentication Logs',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
              ),
            ),
            const SizedBox(height: 16),

            alertsAsync.when(
              data: (alerts) {
                final authLogs = alerts.where((a) => 
                  a.vehicleId == widget.vehicle.vehicleId && 
                  (a.alertType == AlertType.authSuccess || a.alertType == AlertType.authFailure)
                ).toList();

                if (authLogs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(child: Text('No authentication logs found.')),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: authLogs.length,
                  itemBuilder: (context, index) {
                    final log = authLogs[index];
                    final isSuccess = log.alertType == AlertType.authSuccess;

                    // Try to extract the ID and replace it with the name from the profiles list
                    String displayMessage = log.message;
                    final profiles = fingerprintsAsync.asData?.value ?? [];
                    
                    if (isSuccess && displayMessage.contains('Driver ID')) {
                      final match = RegExp(r'Driver ID (\d+)').firstMatch(displayMessage);
                      if (match != null) {
                        final slotId = int.tryParse(match.group(1) ?? '');
                        final profile = profiles.where((p) => p.slotId == slotId).firstOrNull;
                        if (profile != null) {
                          displayMessage = 'Engine Unlocked by ${profile.driverName}';
                        }
                      }
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isDark ? AppColors.dividerDark : AppColors.dividerLight),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: (isSuccess ? AppColors.success : AppColors.danger).withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isSuccess ? Icons.check_circle : Icons.cancel,
                              color: isSuccess ? AppColors.success : AppColors.danger,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayMessage,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat('MMM d, yyyy • hh:mm a').format(log.timestamp),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            isSuccess ? 'Authorized' : 'Failed',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isSuccess ? AppColors.success : AppColors.danger,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error loading logs: $err')),
            ),
          ],
        ),
      ),
    );
  }
}

class PendingCountdownBadge extends StatefulWidget {
  final DateTime createdAt;

  const PendingCountdownBadge({Key? key, required this.createdAt}) : super(key: key);

  @override
  State<PendingCountdownBadge> createState() => _PendingCountdownBadgeState();
}

class _PendingCountdownBadgeState extends State<PendingCountdownBadge> {
  late Timer _timer;
  int _secondsLeft = 65;

  @override
  void initState() {
    super.initState();
    _updateTimer();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateTimer();
    });
  }

  void _updateTimer() {
    final elapsed = DateTime.now().difference(widget.createdAt).inSeconds;
    final left = 65 - elapsed;
    if (mounted) {
      setState(() {
        _secondsLeft = left > 0 ? left : 0;
      });
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_secondsLeft <= 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.danger.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text('Timeout', style: TextStyle(color: AppColors.danger, fontSize: 10, fontWeight: FontWeight.bold)),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
          ),
          const SizedBox(width: 4),
          Text('Pending... ${_secondsLeft}s', style: const TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

