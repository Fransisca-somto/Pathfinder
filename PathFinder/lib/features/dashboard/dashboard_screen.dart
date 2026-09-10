import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/enums/user_role.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/mqtt_service.dart';
import '../../core/providers/socket_provider.dart';

import 'widgets/home_tab.dart';
import 'widgets/map_tab.dart';
import 'widgets/alerts_tab.dart';
import 'widgets/fleet_tab.dart';
import 'widgets/profile_tab.dart';
import 'widgets/driver_dashboard_tab.dart';
import 'widgets/driver_trips_tab.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Start mock MQTT stream
    ref.read(mqttServiceProvider).connect();
    // Initialize actual WebSocket connection
    ref.read(socketServiceProvider);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh global data when app comes to foreground
      ref.invalidate(vehiclesProvider);
      ref.invalidate(zonesProvider);
      ref.invalidate(alertsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final isDriver = user.role == UserRole.driver;
    
    // Watch global index instead of local state
    var currentIndex = ref.watch(dashboardIndexProvider);

    // Listen to real-time alerts globally
    ref.listen(newAlertProvider, (previous, next) {
      if (next.hasValue) {
        final alert = next.value!;
        final message = alert['message'] ?? 'New Alert Received';
        final type = alert['type'] ?? 'UNKNOWN';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(type == 'CRASH_DETECTED' || type == 'SOS_BUTTON' ? Icons.warning : Icons.info, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(message)),
              ],
            ),
            backgroundColor: type == 'CRASH_DETECTED' || type == 'SOS_BUTTON' ? Colors.red : Colors.orange,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );

        // Add the alert to the Alerts list automatically
        ref.read(alertsProvider.notifier).addAlert(alert);

        // Auto-refresh the vehicles provider if the engine lock status changed
        if (type == 'authSuccess' || type == 'authFailure') {
          ref.invalidate(vehiclesProvider);
        }
      }
    });

    // Listen to real-time telemetry globally and update vehicles provider directly
    ref.listen(liveTelemetryProvider, (previous, next) {
      if (next.hasValue && next.value != null) {
        ref.read(vehiclesProvider.notifier).updateTelemetry(next.value!);
      }
    });

    // Define tabs based on role
    final List<Widget> tabs = isDriver 
        ? [
            const DriverDashboardTab(),
            const DriverTripsTab(),
            const AlertsTab(),
          ]
        : [
            const HomeTab(),
            const MapTab(),
            const AlertsTab(),
            const FleetTab(),
            const ProfileTab(),
          ];

    final List<BottomNavigationBarItem> navItems = isDriver
        ? [
            const BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'Dashboard'),
            const BottomNavigationBarItem(icon: Icon(Icons.route_outlined), activeIcon: Icon(Icons.route), label: 'My Trips'),
            const BottomNavigationBarItem(icon: Icon(Icons.notifications_outlined), activeIcon: Icon(Icons.notifications), label: AppStrings.alerts),
          ]
        : [
            const BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: AppStrings.home),
            const BottomNavigationBarItem(icon: Icon(Icons.map_outlined), activeIcon: Icon(Icons.map), label: AppStrings.map),
            const BottomNavigationBarItem(icon: Icon(Icons.notifications_outlined), activeIcon: Icon(Icons.notifications), label: AppStrings.alerts),
            const BottomNavigationBarItem(icon: Icon(Icons.directions_car_outlined), activeIcon: Icon(Icons.directions_car), label: AppStrings.fleet),
            const BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: AppStrings.profile),
          ];

    // Ensure index doesn't go out of bounds if role changes
    if (currentIndex >= tabs.length) {
      currentIndex = 0;
      // We schedule the state update to avoid 'modifying providers during build' error
      Future.microtask(() => ref.read(dashboardIndexProvider.notifier).setIndex(0));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: tabs,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
              width: 1,
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: (index) => ref.read(dashboardIndexProvider.notifier).setIndex(index),
          items: navItems,
          type: BottomNavigationBarType.fixed,
        ),
      ),
    );
  }
}
