import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SocketService {
  late IO.Socket _socket;
  
  // Stream controllers to broadcast events to the UI
  final _liveTelemetryController = StreamController<Map<String, dynamic>>.broadcast();
  final _newAlertController = StreamController<Map<String, dynamic>>.broadcast();
  final _newMediaController = StreamController<Map<String, dynamic>>.broadcast();

  // Getters for the streams
  Stream<Map<String, dynamic>> get liveTelemetryStream => _liveTelemetryController.stream;
  Stream<Map<String, dynamic>> get newAlertStream => _newAlertController.stream;
  Stream<Map<String, dynamic>> get newMediaStream => _newMediaController.stream;

  String? _userId;

  void connect({String? userId}) {
    _userId = userId;
    final apiUrl = dotenv.env['WS_URL'] ?? dotenv.env['API_URL'] ?? '';
    if (apiUrl.isEmpty) {
      debugPrint('[WebSocket] WS_URL/API_URL not set in .env file');
      return;
    }
    
    _socket = IO.io(apiUrl, IO.OptionBuilder()
      .setTransports(['websocket']) // Force WebSocket for better performance
      .disableAutoConnect()
      .build()
    );

    _socket.connect();

    _socket.onConnect((_) {
      debugPrint('[WebSocket] Connected to server');
      // Join the user's private room so we only get our own vehicle data
      if (_userId != null) {
        _socket.emit('authenticate_user', _userId);
        debugPrint('[WebSocket] Authenticated as user: $_userId');
      }
    });

    _socket.onDisconnect((_) {
      debugPrint('[WebSocket] Disconnected from server');
    });

    _socket.onError((error) {
      debugPrint('[WebSocket] Error: $error');
    });

    // Listeners for global events (Alerts)
    _socket.on('new_alert', (data) {
      debugPrint('[WebSocket] New Alert Received: $data');
      _newAlertController.add(Map<String, dynamic>.from(data));
    });

    // Listeners for vehicle-specific events
    _socket.on('live_telemetry', (data) {
      _liveTelemetryController.add(Map<String, dynamic>.from(data));
    });

    _socket.on('new_media', (data) {
      debugPrint('[WebSocket] New Media Received: $data');
      _newMediaController.add(Map<String, dynamic>.from(data));
    });
  }

  // Subscribe to updates for a specific vehicle
  void subscribeVehicle(String vehicleId) {
    if (_socket.connected) {
      debugPrint('[WebSocket] Subscribing to vehicle: $vehicleId');
      _socket.emit('subscribe_vehicle', vehicleId);
    }
  }

  // Unsubscribe when leaving the screen
  void unsubscribeVehicle(String vehicleId) {
    if (_socket.connected) {
      debugPrint('[WebSocket] Unsubscribing from vehicle: $vehicleId');
      _socket.emit('unsubscribe_vehicle', vehicleId);
    }
  }

  void disconnect() {
    _socket.disconnect();
    _socket.dispose();
  }

  void dispose() {
    _liveTelemetryController.close();
    _newAlertController.close();
    _newMediaController.close();
    disconnect();
  }
}
