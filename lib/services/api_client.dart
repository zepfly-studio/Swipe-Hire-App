import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, SocketException;
import 'package:flutter/foundation.dart' show VoidCallback, kDebugMode, kIsWeb, kReleaseMode, visibleForTesting;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

/// Thrown for any failed call to the backend; [message] is safe to show.
/// [statusCode] is the HTTP status, or `0` when no response arrived at all
/// (offline, DNS failure, timeout) -- see [isNetworkError].
class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.body = const {}});
  final int statusCode;
  final String message;

  /// The decoded JSON body, for answers that carry more than a message
  /// (e.g. `needsRole` on a first Google sign-in).
  final Map<String, dynamic> body;

  /// The request never got an answer; the server may be perfectly fine.
  bool get isNetworkError => statusCode == 0;

  /// The server is having a problem (as opposed to rejecting the request).
  bool get isServerError => statusCode >= 500;

  @override
  String toString() => message;
}

/// What the backend hands back on signup/login: the profile plus the Firebase
/// custom token the app signs into Firebase Auth with (see [AuthService]).
class ApiSession {
  const ApiSession({required this.firebaseToken, required this.user});
  final String firebaseToken;
  final Map<String, dynamic> user;
}

/// Talks to the Node/Express backend in `backend/` (endpoint list in
/// `backend/README.md`) and keeps its JWT in a Hive box so the session
/// survives restarts without a network round-trip. Every piece of app data
/// (profiles, jobs, applications, chat, swipes) lives in that backend's
/// Postgres database and goes through the generic [get]/[post]/[put]/
/// [patch]/[delete] helpers here; Firebase is only the auth session.
///
/// [baseUrl] comes from `--dart-define=API_BASE_URL=https://...` (required
/// for any release build). Debug builds fall back to the local backend;
/// "localhost" means the Android emulator itself there, so it uses the
/// `10.0.2.2` host-loopback alias instead. Set [baseUrl] to the dev
/// machine's LAN IP for a physical device.
class ApiClient {
  ApiClient._internal()
      : _client = http.Client(),
        _timeout = _defaultTimeout;

  /// A client with an injected HTTP client and timeout -- tests only.
  @visibleForTesting
  ApiClient.forTest({http.Client? client, Duration timeout = _defaultTimeout})
      : _client = client ?? http.Client(),
        // ignore: prefer_initializing_formals
        _timeout = timeout;

  final http.Client _client;
  final Duration _timeout;

  static final ApiClient instance = ApiClient._internal();

  static const _tokenBox = 'auth_token_box';
  static const _tokenKey = 'token';
  static const _configuredBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// How long to wait for the server before giving up.
  static const Duration _defaultTimeout = Duration(seconds: 20);

  late String baseUrl = _defaultBaseUrl();

  /// Called when an authenticated request is answered with 401, meaning the
  /// saved session is no longer valid. [AuthService] uses it to sign out so
  /// the user lands on the login screen instead of a screen that can't load.
  VoidCallback? onUnauthorized;

  static String _defaultBaseUrl() {
    if (_configuredBaseUrl.isNotEmpty) {
      if (kReleaseMode && !_configuredBaseUrl.startsWith('https://')) {
        throw StateError('API_BASE_URL must use https:// in a release build (got $_configuredBaseUrl).');
      }
      return _configuredBaseUrl;
    }
    if (!kDebugMode) {
      throw StateError('API_BASE_URL is not set -- build with --dart-define=API_BASE_URL=https://your-backend');
    }
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:4000';
    return 'http://localhost:4000';
  }

  Box? _box;

  Future<Box> _openBox() async {
    if (_box != null) return _box!;
    // Hive.initFlutter() has already run in main(); tests call Hive.init().
    _box = await Hive.openBox(_tokenBox);
    return _box!;
  }

  Future<String?> get token async => (await _openBox()).get(_tokenKey) as String?;

  Future<void> _saveToken(String token) async => (await _openBox()).put(_tokenKey, token);

  Future<void> _clearToken() async => (await _openBox()).delete(_tokenKey);

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool auth = false,
    bool signOutOn401 = true,
  }) async {
    final headers = <String, String>{};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (auth) {
      final t = await token;
      if (t != null) headers['Authorization'] = 'Bearer $t';
    }
    var uri = Uri.parse('$baseUrl$path');
    if (query != null && query.isNotEmpty) uri = uri.replace(queryParameters: query);
    final encoded = body == null ? null : jsonEncode(body);
    final http.Response response;
    try {
      final request = switch (method) {
        'GET' => _client.get(uri, headers: headers),
        'PUT' => _client.put(uri, headers: headers, body: encoded),
        'PATCH' => _client.patch(uri, headers: headers, body: encoded),
        'DELETE' => _client.delete(uri, headers: headers),
        _ => _client.post(uri, headers: headers, body: encoded),
      };
      response = await request.timeout(_timeout);
    } on TimeoutException {
      throw ApiException(0, 'The server took too long to respond. Please try again.');
    } on SocketException {
      throw ApiException(0, 'Network error. Check your connection and try again.');
    } on http.ClientException {
      throw ApiException(0, 'Network error. Check your connection and try again.');
    }

    final ok = response.statusCode >= 200 && response.statusCode < 300;
    Map<String, dynamic> decoded = const {};
    if (response.body.isNotEmpty) {
      try {
        final parsed = jsonDecode(response.body);
        if (parsed is Map<String, dynamic>) decoded = parsed;
      } on FormatException {
        // A proxy's HTML error page, for instance. Handled below.
      }
    }
    if (ok) {
      if (response.body.isNotEmpty && decoded.isEmpty) {
        throw ApiException(response.statusCode, 'The server sent an unexpected response. Please try again.');
      }
      return decoded;
    }

    if (response.statusCode == 401 && auth && signOutOn401) onUnauthorized?.call();
    final fallback = response.statusCode >= 500
        ? 'The server is having trouble right now. Please try again in a moment.'
        : 'Something went wrong. Please try again.';
    throw ApiException(response.statusCode, decoded['error'] as String? ?? fallback, body: decoded);
  }

  // -- Generic authenticated calls used by the data services --------------

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) =>
      _request('GET', path, query: query, auth: true);

  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body}) =>
      _request('POST', path, body: body ?? const {}, auth: true);

  Future<Map<String, dynamic>> put(String path, {Map<String, dynamic>? body}) =>
      _request('PUT', path, body: body ?? const {}, auth: true);

  Future<Map<String, dynamic>> patch(String path, {Map<String, dynamic>? body}) =>
      _request('PATCH', path, body: body ?? const {}, auth: true);

  Future<Map<String, dynamic>> delete(String path) => _request('DELETE', path, auth: true);

  // -- Auth ---------------------------------------------------------------

  ApiSession _session(Map<String, dynamic> res) {
    return ApiSession(
      firebaseToken: res['firebaseToken'] as String,
      user: res['user'] as Map<String, dynamic>,
    );
  }

  /// Returns the OTP itself while the backend runs in dev mode (no email
  /// provider configured yet); empty once codes are actually emailed.
  Future<String> sendSignupOtp(String email) async {
    final res = await _request('POST', '/auth/otp/send', body: {'email': email});
    return res['otp'] as String? ?? '';
  }

  Future<void> verifySignupOtp({required String email, required String otp}) =>
      _request('POST', '/auth/otp/verify', body: {'email': email, 'otp': otp});

  Future<ApiSession> signUp({
    required String name,
    required String email,
    required String password,
    required String role,
    String company = '',
  }) async {
    final res = await _request('POST', '/auth/signup', body: {
      'name': name,
      'email': email,
      'password': password,
      'role': role,
      'company': company,
    });
    await _saveToken(res['token'] as String);
    return _session(res);
  }

  Future<ApiSession> signIn({required String email, required String password}) async {
    final res = await _request('POST', '/auth/login', body: {'email': email, 'password': password});
    await _saveToken(res['token'] as String);
    return _session(res);
  }

  /// Exchanges a Firebase ID token from "Continue with Google" for a
  /// session. A first-time Google account must say which [role] it is for;
  /// until it does the backend answers 409 with `needsRole: true`.
  Future<ApiSession> googleSignIn({required String idToken, String? role}) async {
    final res = await _request('POST', '/auth/google', body: {'idToken': idToken, 'role': ?role});
    await _saveToken(res['token'] as String);
    return _session(res);
  }

  /// Confirms [password] for the signed-in user and returns a fresh Firebase
  /// custom token.
  Future<String> reauth(String password) async {
    // A 401 here means "wrong password", not "session expired".
    final res = await _request('POST', '/auth/reauth', body: {'password': password}, auth: true, signOutOn401: false);
    return res['firebaseToken'] as String;
  }

  /// Same dev-mode OTP behaviour as [sendSignupOtp].
  Future<String> forgotPassword(String email) async {
    final res = await _request('POST', '/auth/password/forgot', body: {'email': email});
    return res['otp'] as String? ?? '';
  }

  Future<void> resetPassword({required String email, required String otp, required String newPassword}) =>
      _request('POST', '/auth/password/reset', body: {'email': email, 'otp': otp, 'newPassword': newPassword});

  /// Null when there's no saved session or the backend says it is no longer
  /// valid. Network and server failures are rethrown so callers can tell
  /// "signed out" from "can't reach the server right now".
  Future<Map<String, dynamic>?> fetchMe() async {
    if (await token == null) return null;
    try {
      return await _request('GET', '/users/me', auth: true);
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> updateMe(Map<String, dynamic> fields) =>
      _request('PATCH', '/users/me', body: fields, auth: true);

  Future<void> deleteMe() => _request('DELETE', '/users/me', auth: true);

  Future<void> signOut() => _clearToken();
}
