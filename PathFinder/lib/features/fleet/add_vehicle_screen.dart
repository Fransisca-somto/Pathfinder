import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/api_client.dart';
import '../../shared/widgets/custom_button.dart';
import '../../shared/widgets/custom_button.dart';
import '../../shared/widgets/custom_textfield.dart';
import '../../shared/widgets/qr_scanner_screen.dart';

class AddVehicleScreen extends ConsumerStatefulWidget {
  const AddVehicleScreen({super.key});

  @override
  ConsumerState<AddVehicleScreen> createState() => _AddVehicleScreenState();
}

class _AddVehicleScreenState extends ConsumerState<AddVehicleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _plateController = TextEditingController();
  final _deviceIdController = TextEditingController();
  String _selectedType = 'Car';
  bool _isLoading = false;
  String? _errorMessage;

  void _handleAdd() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      try {
        final apiClient = ref.read(apiClientProvider);
        final response = await apiClient.post('/vehicles/register', {
          'deviceId': _deviceIdController.text.trim(),
          'name': _nameController.text.trim(),
          'plateNumber': _plateController.text.trim().toUpperCase(),
          'type': _selectedType,
        });

        if (!mounted) return;

        // Refresh the vehicles list from the API
        ref.invalidate(vehiclesProvider);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_nameController.text} registered successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      } catch (e) {
        setState(() {
          if (e.toString().contains('409')) {
            _errorMessage = 'This device is already registered.';
          } else {
            _errorMessage = 'Failed to register vehicle. Please try again.';
          }
        });
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _scanQRCode() async {
    // On web show a dialog for manual entry
    if (kIsWeb) {
      _showManualEntryDialog();
      return;
    }

    final status = await Permission.camera.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera permission is required to scan QR codes.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final result = await Navigator.push<String?>(
      context,
      MaterialPageRoute(builder: (context) => const QRScannerScreen()),
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        _deviceIdController.text = result;
      });
    }
  }

  void _showManualEntryDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppColors.surfaceDark
            : AppColors.surfaceLight,
        title: Text(
          'Enter Device ID',
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark
                ? AppColors.textPrimaryDark
                : AppColors.textPrimaryLight,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Find the Device ID on the sticker on your tracker device (e.g., A1B2C3D4E5F6)',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'e.g. A1B2C3D4E5F6',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondary),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                _deviceIdController.text = controller.text.trim().toUpperCase();
                Navigator.pop(ctx);
              }
            },
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeCard(String type, IconData icon, bool isDark) {
    final isSelected = _selectedType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedType = type),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected 
                ? (isDark ? AppColors.secondary.withOpacity(0.2) : AppColors.secondary.withOpacity(0.1))
                : (isDark ? AppColors.surfaceDark : AppColors.surfaceLight),
            border: Border.all(
              color: isSelected ? AppColors.secondary : (isDark ? AppColors.dividerDark : AppColors.dividerLight),
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? AppColors.secondary : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
              const SizedBox(height: 8),
              Text(
                type,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? AppColors.secondary : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add New Vehicle'),
        backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        foregroundColor: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
        iconTheme: IconThemeData(color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Device ID Section
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.secondary.withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.memory, color: AppColors.secondary, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Tracker Device',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Scan the QR code on your tracker or enter the Device ID manually.',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: CustomTextField(
                              label: 'Device ID',
                              hint: 'e.g. A1B2C3D4E5F6',
                              controller: _deviceIdController,
                              prefixIcon: Icons.qr_code,
                              validator: (val) => val!.isEmpty ? 'Device ID is required' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.secondary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
                              onPressed: _scanQRCode,
                              tooltip: 'Scan QR Code',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Vehicle Type
                Text(
                  'Vehicle Type',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildTypeCard('Car', Icons.directions_car, isDark),
                    _buildTypeCard('Truck', Icons.local_shipping, isDark),
                    _buildTypeCard('Van', Icons.airport_shuttle, isDark),
                  ],
                ),
                const SizedBox(height: 24),
                CustomTextField(
                  label: 'Vehicle Name',
                  hint: 'e.g. Delivery Van 1',
                  controller: _nameController,
                  validator: (val) => val!.isEmpty ? AppStrings.errorRequired : null,
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  label: 'License Plate Number',
                  hint: 'e.g. LAG-123-AB',
                  controller: _plateController,
                  validator: (val) => val!.isEmpty ? AppStrings.errorRequired : null,
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.danger.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: AppColors.danger, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 40),
                CustomButton(
                  label: 'Register Vehicle',
                  onPressed: _handleAdd,
                  isLoading: _isLoading,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}



