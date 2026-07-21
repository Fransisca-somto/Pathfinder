import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../enums/user_role.dart';
import '../models/user_model.dart';
import '../utils/dummy_data.dart';
import 'api_client.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return AuthService(apiClient);
});

class AuthService {
  final ApiClient _apiClient;
  final _storage = const FlutterSecureStorage();

  UserModel? _currentUser;
  
  AuthService(this._apiClient);

  UserModel? get currentUser => _currentUser;
  UserRole? get currentUserRole => _currentUser?.role;

  // Real login function hitting the backend
  Future<bool> login(String email, String password) async {
    try {
      final response = await _apiClient.post('/auth/login', {
        'email': email,
        'password': password,
      });

      if (response != null && response['token'] != null) {
        final token = response['token'];
        await _storage.write(key: 'jwt_token', value: token);
        
        final userJson = response['user'];
        _currentUser = UserModel.fromJson(userJson);
        return true;
      }
      return false;
    } catch (e) {
      print('Login error: $e');
      return false;
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required String role,
  }) async {
    try {
      final response = await _apiClient.post('/auth/register', {
        'email': email,
        'password': password,
        'fullName': fullName,
        'phone': phone,
        'role': role.toLowerCase(),
      });

      if (response != null && response['token'] != null) {
        final token = response['token'];
        await _storage.write(key: 'jwt_token', value: token);
        
        final userJson = response['user'];
        _currentUser = UserModel.fromJson(userJson);
        return true;
      } else if (response != null && response['message'] != null) {
        // Success but no token (e.g., email confirmation required)
        return true;
      }
      return false;
    } catch (e) {
      print('Register error: $e');
      return false;
    }
  }

  Future<void> logout() async {
    _currentUser = null;
    await _storage.delete(key: 'jwt_token');
  }

  // Load existing token on startup
  Future<bool> loadUser() async {
    final token = await _storage.read(key: 'jwt_token');
    if (token != null) {
      // In a real app, you might hit a /auth/me endpoint here to get full details.
      // For now, we return true if we have a token.
      return true;
    }
    return false;
  }
}
