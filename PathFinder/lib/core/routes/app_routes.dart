import 'package:flutter/material.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../features/onboarding/setup_wizard_screen.dart';

import '../../features/dashboard/dashboard_screen.dart';
import '../../features/fleet/add_vehicle_screen.dart';
import '../../features/fleet/vehicle_detail_screen.dart';
import '../../features/fleet/vehicle_settings_screen.dart';
import '../../features/zones/zone_management_screen.dart';
import '../../features/fleet/driver_auth_screen.dart';
import '../../features/fleet/route_history_screen.dart';
import '../../features/dashboard/widgets/system_performance_screen.dart';
import '../../core/models/vehicle_model.dart';

import '../../features/profile/edit_profile_screen.dart';
import '../../features/profile/push_notifications_screen.dart';
import '../../features/profile/privacy_security_screen.dart';
import '../../features/profile/help_support_screen.dart';
import '../../features/profile/user_management_screen.dart';
import '../../features/reports/fleet_event_log_screen.dart';
import '../../features/zones/draw_zone_screen.dart';
import '../../core/models/zone_model.dart';

class AppRoutes {
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';
  static const String setupWizard = '/setup-wizard';
  static const String dashboard = '/dashboard';
  static const String addVehicle = '/add-vehicle';
  static const String vehicleDetail = '/vehicle-detail';
  static const String vehicleDetailsPlural = '/vehicle-details';
  static const String vehicleSettings = '/vehicle-settings';
  static const String zoneManagement = '/zone-management';
  static const String driverAuth = '/driver-auth';
  static const String routeHistory = '/route-history';
  static const String systemPerformance = '/system-performance';
  
  static const String editProfile = '/edit-profile';
  static const String pushNotifications = '/push-notifications';
  static const String privacySecurity = '/privacy-security';
  static const String helpSupport = '/help-support';
  static const String userManagement = '/user-management';
  static const String fleetEventLog = '/fleet-event-log';
  static const String drawZone = '/draw-zone';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return MaterialPageRoute(builder: (_) => const SplashScreen());
      case onboarding:
        return MaterialPageRoute(builder: (_) => const OnboardingScreen());
      case login:
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      case register:
        return MaterialPageRoute(builder: (_) => const RegisterScreen());
      case forgotPassword:
        return MaterialPageRoute(builder: (_) => const ForgotPasswordScreen());
      case setupWizard:
        return MaterialPageRoute(builder: (_) => const SetupWizardScreen());
      case dashboard:
        return MaterialPageRoute(builder: (_) => const DashboardScreen());
      case addVehicle:
        return MaterialPageRoute(builder: (_) => const AddVehicleScreen());
      case vehicleDetail:
      case vehicleDetailsPlural:
        final vehicle = settings.arguments as VehicleModel?;
        if (vehicle == null) {
          return MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Error')),
              body: const Center(child: Text('Vehicle data not provided. Please navigate from the fleet list.')),
            ),
          );
        }
        return MaterialPageRoute(builder: (_) => VehicleDetailScreen(vehicle: vehicle));
      case vehicleSettings:
        final vehicle = settings.arguments as VehicleModel;
        return MaterialPageRoute(builder: (_) => VehicleSettingsScreen(vehicle: vehicle));
      case zoneManagement:
        return MaterialPageRoute(builder: (_) => const ZoneManagementScreen());
      case driverAuth:
        final vehicle = settings.arguments as VehicleModel;
        return MaterialPageRoute(builder: (_) => DriverAuthScreen(vehicle: vehicle));
      case routeHistory:
        final vehicle = settings.arguments as VehicleModel;
        return MaterialPageRoute(builder: (_) => RouteHistoryScreen(vehicle: vehicle));
      case systemPerformance:
        return MaterialPageRoute(builder: (_) => const SystemPerformanceScreen());
      case editProfile:
        return MaterialPageRoute(builder: (_) => const EditProfileScreen());
      case pushNotifications:
        return MaterialPageRoute(builder: (_) => const PushNotificationsScreen());
      case privacySecurity:
        return MaterialPageRoute(builder: (_) => const PrivacySecurityScreen());
      case helpSupport:
        return MaterialPageRoute(builder: (_) => const HelpSupportScreen());
      case userManagement:
        return MaterialPageRoute(builder: (_) => const UserManagementScreen());
      case fleetEventLog:
        return MaterialPageRoute(builder: (_) => const FleetEventLogScreen());
      case drawZone:
        final existingZone = settings.arguments as ZoneModel?;
        return MaterialPageRoute(builder: (_) => DrawZoneScreen(existingZone: existingZone));
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(child: Text('No route defined for ${settings.name}')),
          ),
        );
    }
  }
}
