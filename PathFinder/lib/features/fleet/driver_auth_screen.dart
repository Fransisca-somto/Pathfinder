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
import '../../core/providers/socket_provider.dart';
import 'package:intl/intl.dart';

class DriverAuthScreen extends ConsumerStatefulWidget {
  final VehicleModel vehicle;

  const DriverAuthScreen({super.key, required this.vehicle});

  @override
  ConsumerState<DriverAuthScreen> createState() => _DriverAuthScreenState();
}

class _DriverAuthScreenState extends ConsumerState<DriverAuthScreen> {
  final ValueNotifier<bool> bypassState = ValueNotifier<bool>(false);
  bool _isBypassPending = false;

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
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => EnrollmentWizardDialog(vehicle: widget.vehicle),
    );
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
        // Only react to alerts belonging to this vehicle
        if (latestAlert.vehicleId != widget.vehicle.vehicleId) return;

        if (latestAlert.alertType == AlertType.enrollSuccess) {
          // Firmware confirmed enrollment — refresh the profile list
          ref.invalidate(fingerprintsProvider(widget.vehicle.vehicleId));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Fingerprint enrolled successfully!'),
                backgroundColor: AppColors.success,
              ),
            );
          }
        } else if (latestAlert.alertType == AlertType.enrollFailed) {
          // Firmware timed out or failed — refresh list (pending row is gone from DB)
          ref.invalidate(fingerprintsProvider(widget.vehicle.vehicleId));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(latestAlert.message.isNotEmpty
                    ? latestAlert.message
                    : 'Enrollment failed. No finger detected.'),
                backgroundColor: AppColors.danger,
              ),
            );
          }
        } else if (latestAlert.alertType == AlertType.enrollProgress) {
          // Show step feedback so user knows the sensor is responding
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(latestAlert.message),
                duration: const Duration(seconds: 2),
                backgroundColor: Colors.orange,
              ),
            );
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
                    value: isBypassed,
                    activeColor: AppColors.danger,
                    onChanged: _isBypassPending ? null : (val) async {
                      try {
                        setState(() { _isBypassPending = true; });
                        final apiClient = ref.read(apiClientProvider);
                        await apiClient.post('/vehicles/${widget.vehicle.vehicleId}/auth-bypass', {
                          'state': val
                        });
                        
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Bypass command sent. Waiting for confirmation...')),
                          );
                        }
                        
                        // Clear pending state after 5 seconds to prevent getting stuck
                        Future.delayed(const Duration(seconds: 5), () {
                          if (mounted) {
                            setState(() { _isBypassPending = false; });
                          }
                        });
                      } catch (e) {
                        if (mounted) {
                          setState(() { _isBypassPending = false; });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to update bypass state: $e')),
                          );
                        }
                      }
                    },
                    subtitle: _isBypassPending 
                      ? const Text('Command pending...', style: TextStyle(color: Colors.orange))
                      : Text(
                          'If enabled, anyone can start the vehicle without a fingerprint.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                          ),
                        ),
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
                            if (profile.status == 'pending')
                              const Text('Pending Enrollment...', style: TextStyle(color: Colors.orange, fontSize: 12))
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
                    
                    if (log.driverId != null && log.driverId! > 0) {
                      final profile = profiles.where((p) => p.slotId == log.driverId).firstOrNull;
                      if (profile != null) {
                        if (isSuccess) {
                          displayMessage = 'Engine Unlocked by ${profile.driverName}';
                        } else {
                          displayMessage = 'Authentication failed for ${profile.driverName}';
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

class EnrollmentWizardDialog extends ConsumerStatefulWidget {
  final VehicleModel vehicle;
  const EnrollmentWizardDialog({super.key, required this.vehicle});

  @override
  ConsumerState<EnrollmentWizardDialog> createState() => _EnrollmentWizardDialogState();
}

class _EnrollmentWizardDialogState extends ConsumerState<EnrollmentWizardDialog> {
  final _nameController = TextEditingController();
  bool _isEnrolling = false;
  String _currentStep = '';
  int? _pendingSlotId;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<Map<String, dynamic>>>(newAlertProvider, (previous, next) {
      if (!mounted || !_isEnrolling) return;
      if (next.hasValue && next.value != null) {
        final alert = next.value!;
        if (alert['deviceId'] == widget.vehicle.deviceId) {
          final type = alert['type'];
          final message = alert['message'] ?? '';
          
          if (type == 'enrollProgress') {
            setState(() { _currentStep = message; });
          } else if (type == 'enrollSuccess') {
            if (mounted) Navigator.pop(context); // Close wizard
          } else if (type == 'enrollFailed') {
            setState(() { 
              _currentStep = 'Enrollment failed: $message';
              _isEnrolling = false;
              _pendingSlotId = null;
            });
          }
        }
      }
    });

    return AlertDialog(
      title: const Text('Enroll New Driver'),
      content: _isEnrolling 
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(_currentStep.isEmpty ? 'Initializing...' : _currentStep, textAlign: TextAlign.center),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Driver Name'),
              ),
            ],
          ),
      actions: [
        if (!_isEnrolling)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        if (!_isEnrolling)
          ElevatedButton(
            onPressed: () async {
              final name = _nameController.text.trim();
              if (name.isEmpty) return;

              setState(() { _isEnrolling = true; _currentStep = 'Sending command...'; });
              
              try {
                final apiClient = ref.read(apiClientProvider);
                final response = await apiClient.post('/vehicles/${widget.vehicle.vehicleId}/fingerprints', {
                  'driverName': name,
                });
                ref.invalidate(fingerprintsProvider(widget.vehicle.vehicleId));
                
                if (response is Map<String, dynamic> && response.containsKey('slotId')) {
                  _pendingSlotId = response['slotId'] as int?;
                }
                setState(() { _currentStep = 'Place finger on sensor.'; });
              } catch (e) {
                setState(() { _isEnrolling = false; _currentStep = 'Failed: $e'; });
              }
            },
            child: const Text('Start Enrollment'),
          ),
        if (_isEnrolling)
          TextButton(
            onPressed: () async {
              if (_pendingSlotId != null) {
                try {
                  final apiClient = ref.read(apiClientProvider);
                  await apiClient.delete('/vehicles/${widget.vehicle.vehicleId}/fingerprints/$_pendingSlotId');
                  ref.invalidate(fingerprintsProvider(widget.vehicle.vehicleId));
                } catch (e) {
                  // Ignore
                }
              }
              if (mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text('Cancel Enrollment', style: TextStyle(color: Colors.red)),
          )
      ],
    );
  }
}
