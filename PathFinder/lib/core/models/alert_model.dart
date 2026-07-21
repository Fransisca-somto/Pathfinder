import '../enums/alert_type.dart';

class AlertModel {
  final String alertId;
  final AlertType alertType;
  final String vehicleId;
  final String vehicleName;
  final String message;
  final DateTime timestamp;
  final bool isRead;
  final bool requiresAction;
  final String actionType;

  const AlertModel({
    required this.alertId,
    required this.alertType,
    required this.vehicleId,
    required this.vehicleName,
    required this.message,
    required this.timestamp,
    this.isRead = false,
    this.requiresAction = false,
    this.actionType = '',
  });

  AlertModel copyWith({
    String? alertId,
    AlertType? alertType,
    String? vehicleId,
    String? vehicleName,
    String? message,
    DateTime? timestamp,
    bool? isRead,
    bool? requiresAction,
    String? actionType,
  }) {
    return AlertModel(
      alertId: alertId ?? this.alertId,
      alertType: alertType ?? this.alertType,
      vehicleId: vehicleId ?? this.vehicleId,
      vehicleName: vehicleName ?? this.vehicleName,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      requiresAction: requiresAction ?? this.requiresAction,
      actionType: actionType ?? this.actionType,
    );
  }

  factory AlertModel.fromJson(Map<String, dynamic> json) {
    return AlertModel(
      alertId: json['id'] ?? '',
      alertType: AlertType.values.firstWhere(
        (e) => e.name.toLowerCase() == (json['type'] as String?)?.toLowerCase(),
        orElse: () => AlertType.system,
      ),
      vehicleId: json['vehicle_id'] ?? '',
      vehicleName: json['vehicle'] != null ? json['vehicle']['name'] : 'Unknown Vehicle',
      message: json['message'] ?? '',
      timestamp: json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.now(),
      isRead: json['is_read'] ?? false,
      requiresAction: json['requires_action'] ?? false,
      actionType: json['action_type'] ?? '', 
    );
  }
}
