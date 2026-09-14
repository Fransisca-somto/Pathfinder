import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/models/vehicle_model.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/api_client.dart';
import '../../shared/widgets/custom_button.dart';

class VehicleSettingsScreen extends ConsumerStatefulWidget {
  final VehicleModel vehicle;

  const VehicleSettingsScreen({super.key, required this.vehicle});

  @override
  ConsumerState<VehicleSettingsScreen> createState() => _VehicleSettingsScreenState();
}

class _VehicleSettingsScreenState extends ConsumerState<VehicleSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _nameController;
  late TextEditingController _plateController;
  TextEditingController? _driversController;
  late TextEditingController _emergencyContactController;
  late String _selectedType;
  late String _updateInterval;
  late String _connectionMode;

  final List<String> _vehicleTypes = ['Car', 'Truck', 'Motorcycle', 'Van'];
  final List<String> _updateIntervals = ['5s', '10s', '30s', '1m', '5m'];
  final List<String> _connectionModes = ['GPRS', 'Satellite', 'LoRaWAN', 'Bluetooth'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.vehicle.vehicleName);
    _plateController = TextEditingController(text: widget.vehicle.plateNumber);
    _driversController = TextEditingController(text: widget.vehicle.assignedDrivers.join(', '));
    _emergencyContactController = TextEditingController(text: widget.vehicle.emergencyContact ?? '');
    _selectedType = _vehicleTypes.contains(widget.vehicle.vehicleType) ? widget.vehicle.vehicleType : _vehicleTypes.first;
    _updateInterval = _updateIntervals.contains(widget.vehicle.updateInterval) ? widget.vehicle.updateInterval : '5s';
    _connectionMode = _connectionModes.contains(widget.vehicle.connectionMode) ? widget.vehicle.connectionMode : 'GPRS';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _plateController.dispose();
    _driversController?.dispose();
    _emergencyContactController.dispose();
    super.dispose();
  }

  void _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      final updatedVehicle = widget.vehicle.copyWith(
        vehicleName: _nameController.text.trim(),
        plateNumber: _plateController.text.trim(),
        assignedDrivers: _driversController?.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList() ?? [],
        vehicleType: _selectedType,
        updateInterval: _updateInterval,
        connectionMode: _connectionMode,
        emergencyContact: _emergencyContactController.text.trim(),
      );

      try {
        await ref.read(vehiclesProvider.notifier).updateVehicle(updatedVehicle);

        // Assign Drivers via the new API endpoint
        final emails = updatedVehicle.assignedDrivers;
        for (var email in emails) {
          if (email.contains('@')) { // Basic email check
            await ref.read(vehiclesProvider.notifier).assignDriver(widget.vehicle.vehicleId, email);
          }
        }

        // Update emergency contact if changed
        final newContact = _emergencyContactController.text.trim();
        if (newContact != (widget.vehicle.emergencyContact ?? '')) {
          final apiClient = ref.read(apiClientProvider);
          await apiClient.post('/vehicles/${widget.vehicle.vehicleId}/emergency-contact', {
            'phoneNumber': newContact,
          });
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved successfully!'), backgroundColor: AppColors.success),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save settings'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  void _deleteVehicle() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Vehicle'),
        content: Text('Are you sure you want to remove "${widget.vehicle.vehicleName}"? This will unlink the tracker device from your account.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.delete('/vehicles/${widget.vehicle.vehicleId}');

      // Refresh the vehicles list
      ref.invalidate(vehiclesProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.vehicle.vehicleName} removed successfully'),
          backgroundColor: AppColors.success,
        ),
      );
      // Pop back to the fleet list
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to remove vehicle. Please try again.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('Basic Information', isDark),
              const SizedBox(height: 16),
              
              // Name Field
              _buildTextField(
                controller: _nameController,
                label: 'Vehicle Name',
                icon: Icons.directions_car,
                isDark: isDark,
              ),
              const SizedBox(height: 16),
              
              // Plate Field
              _buildTextField(
                controller: _plateController,
                label: 'Plate Number',
                icon: Icons.pin,
                isDark: isDark,
              ),
              const SizedBox(height: 16),
              
              // Emergency Contact Field
              _buildTextField(
                controller: _emergencyContactController,
                label: 'Emergency Contact (e.g. +23480...)',
                icon: Icons.phone,
                isDark: isDark,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              
              // Drivers Field
              _buildTextField(
                controller: _driversController ??= TextEditingController(text: widget.vehicle.assignedDrivers.join(', ')),
                label: 'Assigned Driver(s) - Comma separated',
                icon: Icons.person,
                isDark: isDark,
              ),
              const SizedBox(height: 16),
              
              // Type Dropdown
              _buildDropdown(
                label: 'Vehicle Type',
                value: _selectedType,
                items: _vehicleTypes,
                icon: Icons.category,
                isDark: isDark,
                onChanged: (val) {
                  if (val != null) setState(() => _selectedType = val);
                },
              ),
              
              const SizedBox(height: 32),
              _buildSectionHeader('Hardware & Tracking', isDark),
              const SizedBox(height: 16),
              
              // Device ID (Read-only)
              _buildTextField(
                controller: TextEditingController(text: widget.vehicle.deviceId),
                label: 'Tracker Device ID',
                icon: Icons.memory,
                isDark: isDark,
                readOnly: true,
              ),
              const SizedBox(height: 16),
              
              // Update Interval Dropdown
              _buildDropdown(
                label: 'GPS Update Interval',
                value: _updateInterval,
                items: _updateIntervals,
                icon: Icons.timer,
                isDark: isDark,
                onChanged: (val) {
                  if (val != null) setState(() => _updateInterval = val);
                },
              ),
              const SizedBox(height: 16),
              
              // Connection Mode Dropdown
              _buildDropdown(
                label: 'Connection Mode',
                value: _connectionMode,
                items: _connectionModes,
                icon: Icons.wifi_tethering,
                isDark: isDark,
                onChanged: (val) {
                  if (val != null) setState(() => _connectionMode = val);
                },
              ),
              
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: CustomButton(
                  label: 'Save Changes',
                  onPressed: _saveSettings,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _deleteVehicle,
                  icon: const Icon(Icons.delete_forever, color: AppColors.danger),
                  label: const Text('Remove Vehicle', style: TextStyle(color: AppColors.danger)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.danger),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isDark,
    bool readOnly = false,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboardType,
      style: TextStyle(
        color: readOnly 
            ? (isDark ? Colors.grey[600] : Colors.grey[400]) 
            : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
        filled: true,
        fillColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      validator: (value) => (value == null || value.isEmpty) && !readOnly ? 'Required' : null,
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required IconData icon,
    required bool isDark,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        dropdownColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        items: items.map((item) {
          return DropdownMenuItem(
            value: item,
            child: Text(
              item,
              style: TextStyle(color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
            ),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }
}
