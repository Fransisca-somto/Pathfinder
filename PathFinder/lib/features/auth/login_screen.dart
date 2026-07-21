import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/auth_service.dart';
import '../../core/providers/app_providers.dart';
import '../../core/enums/user_role.dart';
import '../../core/models/user_model.dart';
import '../../shared/widgets/custom_button.dart';
import '../../shared/widgets/custom_textfield.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  int _failedAttempts = 0;
  DateTime? _lockoutEndTime;
  Timer? _lockoutTimer;

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    if (_lockoutEndTime != null && DateTime.now().isBefore(_lockoutEndTime!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account locked. Please wait 5 minutes.')),
      );
      return;
    }

    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      
      final authService = ref.read(authServiceProvider);
      final success = await authService.login(
        _emailController.text, 
        _passwordController.text
      );

      if (!mounted) return;
      
      if (success) {
        setState(() {
          _failedAttempts = 0;
          _isLoading = false;
        });
        
        // Invalidate data providers to force a fresh fetch with the new token
        ref.read(currentUserProvider.notifier).setUser(authService.currentUser);
        ref.invalidate(vehiclesProvider);
        ref.invalidate(alertsProvider);
        ref.invalidate(zonesProvider);

        Navigator.pushReplacementNamed(context, AppRoutes.dashboard);
      } else {
        setState(() {
          _failedAttempts++;
          _isLoading = false;
          if (_failedAttempts >= 5) {
            _lockoutEndTime = DateTime.now().add(const Duration(minutes: 5));
            _startLockoutTimer();
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_failedAttempts >= 5 
              ? 'Too many failed attempts. Locked out for 5 minutes.' 
              : 'Invalid credentials. Attempt $_failedAttempts of 5.'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  void _startLockoutTimer() {
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_lockoutEndTime != null && DateTime.now().isAfter(_lockoutEndTime!)) {
        setState(() {
          _lockoutEndTime = null;
          _failedAttempts = 0;
        });
        timer.cancel();
      } else {
        setState(() {}); // Update UI countdown if we want to show it
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header
            Expanded(
              flex: 1,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.satellite_alt, size: 60, color: AppColors.accent),
                    const SizedBox(height: 16),
                    Text(
                      'Welcome Back',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Form Card
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(32.0),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(32),
                    topRight: Radius.circular(32),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        CustomTextField(
                          label: 'Email Address',
                          hint: 'Enter your email',
                          controller: _emailController,
                          prefixIcon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            if (value == null || value.isEmpty) return AppStrings.errorRequired;
                            if (!value.contains('@')) return AppStrings.errorEmail;
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        CustomTextField(
                          label: 'Password',
                          hint: 'Enter your password',
                          controller: _passwordController,
                          prefixIcon: Icons.lock_outline,
                          obscure: true,
                          validator: (value) {
                            if (value == null || value.isEmpty) return AppStrings.errorRequired;
                            if (value.length < 6) return AppStrings.errorPassword;
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => Navigator.pushNamed(context, AppRoutes.forgotPassword),
                            child: const Text(AppStrings.forgotPassword),
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (_lockoutEndTime != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              'Locked out for ${_lockoutEndTime!.difference(DateTime.now()).inMinutes}:${(_lockoutEndTime!.difference(DateTime.now()).inSeconds % 60).toString().padLeft(2, '0')}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold),
                            ),
                          ),
                        CustomButton(
                          label: AppStrings.login,
                          onPressed: _lockoutEndTime == null ? _handleLogin : null,
                          isLoading: _isLoading,
                        ),
                        const SizedBox(height: 16),
                        CustomButton(
                          label: 'Continue with Google',
                          icon: Icons.g_mobiledata,
                          isOutlined: true,
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Coming Soon')),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        CustomButton(
                          label: 'Enter Demo Mode',
                          icon: Icons.science_outlined,
                          isOutlined: true,
                          onPressed: () {
                            // Create a mock owner user for UI testing
                            final mockUser = UserModel(
                              userId: 'DEMO-001',
                              fullName: 'Demo Owner',
                              email: 'demo@pathfinder.com',
                              phone: '+2348000000000',
                              role: UserRole.owner,
                              assignedVehicles: [],
                              createdAt: DateTime.now(),
                            );
                            ref.read(currentUserProvider.notifier).setUser(mockUser);
                            Navigator.pushReplacementNamed(context, AppRoutes.dashboard);
                          },
                        ),
                        const SizedBox(height: 32),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Don't have an account?",
                              style: TextStyle(
                                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pushNamed(context, AppRoutes.register),
                              child: const Text(AppStrings.register),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
