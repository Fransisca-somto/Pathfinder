import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final mqttServiceProvider = Provider<MqttService>((ref) => MqttService());

class MqttService {
  // Connection state stream
  final _connectionController = StreamController<bool>.broadcast();
  Stream<bool> get connectionState => _connectionController.stream;

  // Mock telemetry data streams for testing UI
  final _telemetryController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get telemetryStream => _telemetryController.stream;

  Timer? _mockTimer;

  Future<void> connect() async {
    // Simulate connection delay
    await Future.delayed(const Duration(seconds: 1));
    _connectionController.add(true);
    
    // Start generating mock telemetry data every 5 seconds
    _mockTimer?.cancel();
    _mockTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _telemetryController.add({
        'battery': 85 - (timer.tick % 5),
        'speed': 60 + (timer.tick % 10),
        'gpsFix': true,
        'gsmSignal': 4,
        'ignition': 'on',
      });
    });
  }

  void disconnect() {
    _mockTimer?.cancel();
    _connectionController.add(false);
  }

  // Mock sending a command (like engine cut-off)
  Future<bool> sendCommand(String topic, String payload) async {
    await Future.delayed(const Duration(seconds: 2));
    // Always succeed in mock mode
    return true;
  }
}
