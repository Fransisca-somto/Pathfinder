import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_colors.dart';
import '../../core/routes/app_routes.dart';
import '../../shared/widgets/custom_button.dart';
import '../../shared/widgets/custom_textfield.dart';
import '../../shared/widgets/qr_scanner_screen.dart';

class SetupWizardScreen extends StatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  int _currentStep = 0;
  final _serialController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _serialController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < 2) {
      setState(() => _currentStep++);
    } else {
      // Complete wizard
      Navigator.pushReplacementNamed(context, AppRoutes.dashboard);
    }
  }

  void _scanQRCode() async {
    if (kIsWeb) {
      return;
    }

    try {
      final result = await Navigator.push<String?>(
        context,
        MaterialPageRoute(builder: (context) => const QRScannerScreen()),
      );

      if (result != null && result.isNotEmpty) {
        setState(() {
          _serialController.text = result;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera permission is required to scan QR codes.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup Your Device'),
        automaticallyImplyLeading: false,
      ),
      body: Stepper(
        type: StepperType.horizontal,
        currentStep: _currentStep,
        onStepContinue: _nextStep,
        onStepCancel: () {
          if (_currentStep > 0) {
            setState(() => _currentStep--);
          }
        },
        controlsBuilder: (context, details) {
          return Padding(
            padding: const EdgeInsets.only(top: 32),
            child: Row(
              children: [
                Expanded(
                  child: CustomButton(
                    label: _currentStep == 2 ? 'Complete Setup' : 'Continue',
                    onPressed: () {
                      details.onStepContinue?.call();
                    },
                  ),
                ),
                if (_currentStep > 0) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    child: CustomButton(
                      label: 'Back',
                      isOutlined: true,
                      onPressed: () {
                        details.onStepCancel?.call();
                      },
                    ),
                  ),
                ],
              ],
            ),
          );
        },
        steps: [
          Step(
            title: const Text('Device'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter the device details',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: CustomTextField(
                        label: 'Hardware Serial Number',
                        hint: 'e.g., TRK-ESP32-8821',
                        controller: _serialController,
                        prefixIcon: Icons.qr_code,
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
                const SizedBox(height: 16),
                CustomTextField(
                  label: 'Vehicle Name',
                  hint: 'e.g., Delivery Truck 1',
                  controller: _nameController,
                ),
              ],
            ),
            isActive: _currentStep >= 0,
            state: _currentStep > 0 ? StepState.complete : StepState.indexed,
          ),
          Step(
            title: const Text('Geofence'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Set a Home Zone',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: AppColors.dividerLight,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.map, size: 48, color: AppColors.textSecondaryLight),
                        SizedBox(height: 8),
                        Text('Interactive Map Placeholder'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'You can configure the geofence radius later from Vehicle Settings.',
                  style: TextStyle(color: AppColors.textSecondaryLight),
                ),
              ],
            ),
            isActive: _currentStep >= 1,
            state: _currentStep > 1 ? StepState.complete : StepState.indexed,
          ),
          Step(
            title: const Text('Confirm'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Confirm Registration',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('Serial Number'),
                  subtitle: Text(_serialController.text.isEmpty ? 'Not provided' : _serialController.text),
                  leading: const Icon(Icons.qr_code, color: AppColors.secondary),
                ),
                ListTile(
                  title: const Text('Vehicle Name'),
                  subtitle: Text(_nameController.text.isEmpty ? 'Not provided' : _nameController.text),
                  leading: const Icon(Icons.directions_car, color: AppColors.secondary),
                ),
                const ListTile(
                  title: Text('Home Zone'),
                  subtitle: Text('Configured'),
                  leading: Icon(Icons.location_on, color: AppColors.success),
                ),
                const SizedBox(height: 16),
                const Text(
                  'By completing this setup, your hardware tracker will be paired with this account and begin streaming data immediately.',
                  style: TextStyle(color: AppColors.textSecondaryLight),
                ),
              ],
            ),
            isActive: _currentStep >= 2,
          ),
        ],
      ),
    );
  }
}
