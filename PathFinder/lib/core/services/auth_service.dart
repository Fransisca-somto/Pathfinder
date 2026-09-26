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
        await _storeTokens(response);
        _currentUser = UserModel.fromJson(response['user']);
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
        await _storeTokens(response);
        _currentUser = UserModel.fromJson(response['user']);
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

  /// Logs the user out.
  ///
  /// Calls POST /auth/logout first to revoke the refresh token server-side
  /// (single-session scope — other devices stay logged in). Local tokens are
  /// always cleared in the finally block regardless of server response, so a
  /// failed network call can never leave the user stuck in a logged-in state.
  Future<void> logout() async {
    try {
      await _apiClient.post('/auth/logout', {});
    } catch (_) {
      // Best-effort server revocation. The token will expire naturally even if
      // the network call fails, but the stored refresh_token is cleared below
      // so this device cannot use it again.
    } finally {
      _currentUser = null;
      await _storage.delete(key: 'jwt_token');
      await _storage.delete(key: 'refresh_token');
    }
  }

  /// Called on cold start (from SplashScreen). Restores the session without
  /// forcing a login if a valid refresh token is stored.
  ///
  /// Flow:
  /// 1. If the stored access token has fewer than 60 seconds of life left,
  ///    silently refresh it *before* calling /auth/me. This avoids an
  ///    unnecessary 401 round-trip on a just-expired token.
  /// 2. Call GET /auth/me regardless — the server is the source of truth for
  ///    account status: disabled accounts, remote password changes, and
  ///    vehicle-list changes are all surfaced here.
  /// 3. On [SessionExpiredException] (refresh token gone or revoked), clear
  ///    local state and return false so the caller routes to the login screen.
  Future<bool> loadUser() async {
    final token = await _storage.read(key: 'jwt_token');
    if (token == null) return false;

    try {
      // Pre-flight: refresh if the access token is close to or past expiry.
      // If refresh fails because the refresh token is also gone, ensureFreshToken
      // returns false but does NOT throw — we let /auth/me surface the 401 so
      // _requestWithRefresh can throw SessionExpiredException uniformly.
      await _apiClient.ensureFreshToken(thresholdSeconds: 60);

      // Always verify with the server — local state is not sufficient.
      final response = await _apiClient.get('/auth/me');
      if (response != null && response['user'] != null) {
        _currentUser = UserModel.fromJson(response['user']);
        return true;
      }
    } on SessionExpiredException {
      // The refresh token is invalid or revoked — clean slate.
      await _clearLocalState();
    } catch (e) {
      print('Error loading user profile: $e');
      await _clearLocalState();
    }
    return false;
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  Future<void> _storeTokens(Map<String, dynamic> response) async {
    await _storage.write(key: 'jwt_token', value: response['token'] as String);
    final rt = response['refresh_token'];
    if (rt != null) {
      await _storage.write(key: 'refresh_token', value: rt as String);
    }
  }

  Future<void> _clearLocalState() async {
    _currentUser = null;
    await _storage.delete(key: 'jwt_token');
    await _storage.delete(key: 'refresh_token');
  }
}
