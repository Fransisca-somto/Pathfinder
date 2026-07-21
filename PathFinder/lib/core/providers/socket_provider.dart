import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/socket_service.dart';

import '../providers/app_providers.dart';

// Provider for the SocketService instance
final socketServiceProvider = Provider<SocketService>((ref) {
  final user = ref.watch(currentUserProvider);
  final service = SocketService();
  service.connect(userId: user?.userId);
  
  // Clean up when the provider is disposed
  ref.onDispose(() {
    service.dispose();
  });
  
  return service;
});

// Stream providers for easy consumption in the UI
final liveTelemetryProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final socketService = ref.watch(socketServiceProvider);
  return socketService.liveTelemetryStream;
});

final newAlertProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final socketService = ref.watch(socketServiceProvider);
  return socketService.newAlertStream;
});

final newMediaProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final socketService = ref.watch(socketServiceProvider);
  return socketService.newMediaStream;
});
