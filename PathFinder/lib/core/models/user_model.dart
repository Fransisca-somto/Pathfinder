import '../enums/user_role.dart';

class UserModel {
  final String userId;
  final String fullName;
  final String email;
  final String phone;
  final UserRole role;
  final List<String> assignedVehicles;
  final DateTime createdAt;

  const UserModel({
    required this.userId,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.role,
    this.assignedVehicles = const [],
    required this.createdAt,
  });

  UserModel copyWith({
    String? userId,
    String? fullName,
    String? email,
    String? phone,
    UserRole? role,
    List<String>? assignedVehicles,
    DateTime? createdAt,
  }) {
    return UserModel(
      userId: userId ?? this.userId,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      assignedVehicles: assignedVehicles ?? this.assignedVehicles,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'fullName': fullName,
      'email': email,
      'phone': phone,
      'role': role.name,
      'assignedVehicles': assignedVehicles,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      userId: json['id'] ?? json['userId'] ?? '',
      fullName: json['fullName'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      role: UserRole.values.firstWhere(
        (e) => e.name.toLowerCase() == (json['role'] as String?)?.toLowerCase(),
        orElse: () => UserRole.driver,
      ),
      assignedVehicles: List<String>.from(json['assignedVehicles'] ?? []),
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : DateTime.now(),
    );
  }
}
