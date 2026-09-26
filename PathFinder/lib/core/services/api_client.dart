import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

/// Thrown when a token refresh attempt fails and the user must log in again.
/// Callers (e.g. [AuthService.loadUser]) catch this to navigate to the login
/// screen rather than leaving the app in an unauthenticated-but-stuck state.
class SessionExpiredException implements Exception {
  const SessionExpiredException();
  @override
  String toString() => 'SessionExpiredException: refresh token is invalid or revoked';
}

class ApiClient {
  final _storage = const FlutterSecureStorage();

  // ── Concurrent-refresh guard ─────────────────────────────────────────
  // Supabase rotates the refresh token on every use. If two requests both
  // hit HTTP 401 at the same time (common on the vehicle screen which fires
  // several parallel requests), both would try to refresh and the second
  // would present a token the first already consumed — causing a failure
  // that logs the user out.
  //
  // Solution: hold a single in-flight Future here. Every concurrent 401
  // caller awaits _refreshFuture instead of starting its own request.
  // whenComplete() clears the field so the next genuine expiry can start
  // a fresh refresh. If the refresh fails, the Future rejects and ALL
  // waiters receive the same SessionExpiredException.
  Future<bool>? _refreshFuture;
  // ────────────────────────────────────────────────────────────────────

  String get _baseUrl {
    final url = dotenv.env['API_URL'] ?? '';
    if (url.isEmpty) throw Exception('API_URL is not set in the .env file');
    return url;
  }

  Future<Map<String, String>> _getHeaders() async {
    final headers = {'Content-Type': 'application/json'};
    final token = await _storage.read(key: 'jwt_token');
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  // ── Public HTTP methods ───────────────────────────────────────────────

  Future<dynamic> get(String endpoint) =>
      _requestWithRefresh(() async => http.get(
            Uri.parse('$_baseUrl$endpoint'),
            headers: await _getHeaders(),
          ));

  Future<dynamic> post(String endpoint, Map<String, dynamic> body) =>
      _requestWithRefresh(() async => http.post(
            Uri.parse('$_baseUrl$endpoint'),
            headers: await _getHeaders(),
            body: jsonEncode(body),
          ));

  Future<dynamic> put(String endpoint, Map<String, dynamic> body) =>
      _requestWithRefresh(() async => http.put(
            Uri.parse('$_baseUrl$endpoint'),
            headers: await _getHeaders(),
            body: jsonEncode(body),
          ));

  Future<dynamic> delete(String endpoint) =>
      _requestWithRefresh(() async => http.delete(
            Uri.parse('$_baseUrl$endpoint'),
            headers: await _getHeaders(),
          ));

  // ── Token freshness helpers ───────────────────────────────────────────

  /// Decodes the stored JWT locally (no network) and returns the number of
  /// seconds until it expires. Returns 0 if the token is absent or already
  /// expired. This is used for the pre-flight check on cold start so we
  /// can refresh before hitting /auth/me rather than letting it 401.
  Future<int> accessTokenSecondsRemaining() async {
    final token = await _storage.read(key: 'jwt_token');
    if (token == null) return 0;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return 0;
      // Decode the payload segment — no signature verification needed here;
      // the server verifies on every API call.
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      final exp = payload['exp'] as int?;
      if (exp == null) return 0;
      return exp - (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    } catch (_) {
      return 0;
    }
  }

  /// Ensures the stored access token has at least [thresholdSeconds] of
  /// life left. If not, performs a silent refresh before returning.
  /// Returns true if the token is (or became) fresh; false if refresh failed.
  Future<bool> ensureFreshToken({int thresholdSeconds = 60}) async {
    final remaining = await accessTokenSecondsRemaining();
    if (remaining > thresholdSeconds) return true;
    return _enqueueRefresh();
  }

  // ── Internal helpers ──────────────────────────────────────────────────

  /// Executes [requestFn], and if the server returns HTTP 401, attempts a
  /// single silent token refresh then retries the original request.
  /// Throws [SessionExpiredException] when the refresh token is also invalid.
  Future<dynamic> _requestWithRefresh(
    Future<http.Response> Function() requestFn,
  ) async {
    var response = await requestFn();

    if (response.statusCode == 401) {
      final refreshed = await _enqueueRefresh();
      if (!refreshed) throw const SessionExpiredException();
      // Retry with the newly stored access token
      response = await requestFn();
    }

    return _handleResponse(response);
  }

  /// If no refresh is already running, starts one. If one IS running, returns
  /// the same Future — guaranteeing at most one /auth/refresh call at a time.
  Future<bool> _enqueueRefresh() {
    // Assign and immediately chain whenComplete so the field is cleared
    // regardless of success or failure, allowing the next expiry to refresh.
    _refreshFuture ??= _doRefresh().whenComplete(() {
      _refreshFuture = null;
    });
    return _refreshFuture!;
  }

  /// Calls POST /auth/refresh. On success, persists both the new access token
  /// and the rotated refresh token. On failure, clears both so the app is in
  /// a clean logged-out state.
  Future<bool> _doRefresh() async {
    final storedRefresh = await _storage.read(key: 'refresh_token');
    if (storedRefresh == null) return false;

    try {
      // Bypass _requestWithRefresh to avoid infinite recursion.
      final response = await http.post(
        Uri.parse('$_baseUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': storedRefresh}),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        await _storage.write(key: 'jwt_token',     value: body['token']         as String);
        await _storage.write(key: 'refresh_token', value: body['refresh_token'] as String);
        return true;
      }

      // 401 from /auth/refresh means the refresh token is revoked or expired.
      // Clear both tokens so the app lands on the login screen cleanly.
      await _storage.delete(key: 'jwt_token');
      await _storage.delete(key: 'refresh_token');
      return false;
    } catch (_) {
      // Network error — don't clear tokens; a retry on next app open may work.
      return false;
    }
  }

  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isNotEmpty) return jsonDecode(response.body);
      return null;
    } else {
      throw Exception('API Error: ${response.statusCode} - ${response.body}');
    }
  }
}
