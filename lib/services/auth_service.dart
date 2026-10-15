import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/app_user.dart';
import 'api_client.dart';
import 'in_app_notifier.dart';
import 'inbox_service.dart';
import 'wishlist_service.dart';

/// A first-time Google account has to say whether it is a recruiter or a
/// candidate; the sign-in screen asks and calls
/// [AuthService.signInWithGoogle] again with a role.
class GoogleSignInNeedsRole implements Exception {
  const GoogleSignInNeedsRole();
}

/// Email/password accounts live in the Node/Postgres backend (`backend/`),
/// reached through [ApiClient]. Firebase Auth is kept only as the app's
/// session (what [AuthGate] listens to): the backend mints a custom token
/// for the same uid and this signs into Firebase with it. Every other piece
/// of data lives in Postgres behind the backend -- nothing is mirrored to
/// Firebase.
class AuthService {
  AuthService._internal({FirebaseAuth? auth, ApiClient? api})
      : _auth = auth ?? FirebaseAuth.instance,
        _api = api ?? ApiClient.instance {
    // A request answered with 401 means the saved session expired: sign out
    // so the user is sent to the login screen.
    _api.onUnauthorized = () => unawaited(signOut());
  }
  static final AuthService instance = AuthService._internal();

  /// Builds an instance wired to injected fakes -- used only by tests, never
  /// by app code, which should always go through [instance].
  @visibleForTesting
  factory AuthService.test({required FirebaseAuth auth, required ApiClient api}) =>
      AuthService._internal(auth: auth, api: api);

  final FirebaseAuth _auth;
  final ApiClient _api;

  /// Produces the Firebase ID token for "Continue with Google", or null if
  /// the person closed the Google window. Replaced in tests.
  @visibleForTesting
  Future<String?> Function()? googleIdTokenProvider;

  /// Emits on sign-in and sign-out.
  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  /// The signed-in account's id, or an empty string while signed out. Safe
  /// to read from a screen that may rebuild during sign-out.
  String get currentUid => _auth.currentUser?.uid ?? '';

  /// Maps backend/network failures onto [FirebaseAuthException] so the auth
  /// screens' existing `on FirebaseAuthException` handling (and
  /// `authErrorMessage`) keeps working unchanged.
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on ApiException catch (e) {
      if (e.isNetworkError) {
        throw FirebaseAuthException(code: 'network-request-failed', message: e.message);
      }
      throw FirebaseAuthException(code: 'backend-error', message: e.message);
    }
  }

  AppUser _profileFrom(Map<String, dynamic> user) => AppUser.fromMap(user['uid'] as String, user);

  /// The backend profile for the signed-in account, or null if there's no
  /// valid saved session or it belongs to a different uid than Firebase's.
  /// Throws an [ApiException] when the server can't be reached.
  Future<AppUser?> fetchProfile(String uid) async {
    final user = await _api.fetchMe();
    if (user == null || user['uid'] != uid) return null;
    return _profileFrom(user);
  }

  /// Same as [fetchProfile], but retries a few times when the server can't
  /// be reached (or is erroring) before giving up, so a flaky connection at
  /// launch doesn't fail the whole app. The last error is rethrown, which
  /// [AuthGate] shows as a "can't connect" screen -- it never signs the
  /// user out just because the network was down.
  Future<AppUser?> fetchProfileWithRetry(
    String uid, {
    int attempts = 3,
    Duration gap = const Duration(milliseconds: 800),
  }) async {
    for (var i = 0;; i++) {
      try {
        return await fetchProfile(uid);
      } on ApiException catch (e) {
        final retryable = e.isNetworkError || e.isServerError;
        if (!retryable || i >= attempts - 1) rethrow;
      }
      await Future.delayed(gap);
    }
  }

  /// Sends a 6-digit email OTP for [SignupScreen]'s pre-account-creation
  /// verification step. Call [verifySignupOtp] with the code the user
  /// enters, then [signUp] -- in that order, the account is only ever
  /// created for an email that's already passed OTP verification.
  ///
  /// Returns the code itself while the backend runs without an email
  /// provider (dev mode), so the screen can show it; empty otherwise.
  Future<String> sendSignupOtp(String email) => _guard(() => _api.sendSignupOtp(email.trim()));

  /// Verifies the code from [sendSignupOtp]. Throws a [FirebaseAuthException]
  /// with a message suitable for display if the code is wrong, expired, or
  /// the attempt limit was hit.
  Future<void> verifySignupOtp({required String email, required String otp}) =>
      _guard(() => _api.verifySignupOtp(email: email.trim(), otp: otp.trim()));

  Future<AppUser> signUp({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String company = '',
  }) async {
    final session = await _guard(() => _api.signUp(
          name: name.trim(),
          email: email.trim(),
          password: password,
          role: role.value,
          company: company.trim(),
        ));
    await _auth.signInWithCustomToken(session.firebaseToken);
    return _profileFrom(session.user);
  }

  Future<AppUser> signIn({required String email, required String password}) async {
    final session = await _guard(() => _api.signIn(email: email.trim(), password: password));
    await _auth.signInWithCustomToken(session.firebaseToken);
    return _profileFrom(session.user);
  }

  /// "Continue with Google": signs into Firebase with Google, then trades
  /// that ID token for a normal GlideRecruit session. Returns null if the
  /// person closed the Google window. Throws [GoogleSignInNeedsRole] for a
  /// first-time account until [role] is given.
  Future<AppUser?> signInWithGoogle({UserRole? role}) async {
    final idToken = await (googleIdTokenProvider ?? _googleIdToken)();
    if (idToken == null) return null;
    try {
      final session = await _api.googleSignIn(idToken: idToken, role: role?.value);
      await _auth.signInWithCustomToken(session.firebaseToken);
      return _profileFrom(session.user);
    } on ApiException catch (e) {
      if (e.statusCode == 409 && e.body['needsRole'] == true) throw const GoogleSignInNeedsRole();
      if (e.isNetworkError) {
        throw FirebaseAuthException(code: 'network-request-failed', message: e.message);
      }
      throw FirebaseAuthException(code: 'backend-error', message: e.message);
    }
  }

  Future<String?> _googleIdToken() async {
    final provider = GoogleAuthProvider()..addScope('email');
    try {
      final credential = kIsWeb ? await _auth.signInWithPopup(provider) : await _auth.signInWithProvider(provider);
      return await credential.user?.getIdToken();
    } on FirebaseAuthException catch (e) {
      const cancelled = {'popup-closed-by-user', 'cancelled-popup-request', 'web-context-canceled', 'canceled'};
      if (cancelled.contains(e.code)) return null;
      rethrow;
    }
  }

  /// Starts the forgot-password flow; returns the dev-mode OTP like
  /// [sendSignupOtp]. Follow with [resetPassword].
  Future<String> sendPasswordReset(String email) => _guard(() => _api.forgotPassword(email.trim()));

  Future<void> resetPassword({required String email, required String otp, required String newPassword}) =>
      _guard(() => _api.resetPassword(email: email.trim(), otp: otp.trim(), newPassword: newPassword));

  Future<void> _updateProfile(Map<String, dynamic> fields) async {
    await _guard(() => _api.updateMe(fields));
  }

  /// Saves the remaining recruiter details collected on
  /// [CompleteProfileScreen] and marks the account ready for [RootShell].
  Future<void> completeRecruiterProfile({
    required String designation,
    required String phone,
  }) {
    return _updateProfile({
      'designation': designation.trim(),
      'phone': phone.trim(),
      'profileComplete': true,
    });
  }

  /// Updates the recruiter's own profile fields from [ProfileScreen].
  Future<void> updateRecruiterProfile({
    required String name,
    required String designation,
    required String company,
    required String phone,
  }) {
    return _updateProfile({
      'name': name.trim(),
      'designation': designation.trim(),
      'company': company.trim(),
      'phone': phone.trim(),
    });
  }

  /// Turns the emails that go with notifications on or off.
  Future<void> setEmailNotifications(bool enabled) => _updateProfile({'emailNotifications': enabled});

  /// Marks the account ready for [CandidateRootShell] once
  /// [CandidateProfileService.save] has written the candidate's details.
  Future<void> markCandidateProfileComplete() => _updateProfile({'profileComplete': true});

  /// Who a team invite code is for: {email, companyName}.
  Future<Map<String, dynamic>> inviteInfo(String token) => _guard(() => _api.inviteInfo(token.trim()));

  /// Joins a company as a recruiter with an invite code and signs in.
  Future<AppUser> acceptInvite({required String token, required String name, required String password}) async {
    final session = await _guard(() => _api.acceptInvite(token: token.trim(), name: name.trim(), password: password));
    await _auth.signInWithCustomToken(session.firebaseToken);
    return _profileFrom(session.user);
  }

  /// Changes the password; other devices are signed out. Throws [ApiException]
  /// (its `body['field']` is `current` or `next`) so the form can mark the input.
  Future<void> changePassword({required String current, required String next}) =>
      _api.changePassword(current: current, next: next);

  /// "Log out of all devices": the server kills every token, then this
  /// device signs out too.
  Future<void> logoutAllDevices() async {
    await _api.logoutAll();
    await signOut();
  }

  Future<void> signOut() async {
    WishlistService.instance.clear();
    InAppNotifier.instance.stop();
    InboxService.instance.stop();
    await _api.signOut();
    await _auth.signOut();
  }

  /// Confirms the password with the backend and refreshes the Firebase
  /// session with a new custom token, for use before a sensitive action.
  Future<void> reauthenticateWithPassword(String password) async {
    final firebaseToken = await _guard(() => _api.reauth(password));
    await _auth.signInWithCustomToken(firebaseToken);
  }

  /// Deletes the account on the backend, which cascades to everything it
  /// owns in Postgres (candidate profile, saved jobs, every opportunity
  /// where it's the candidate OR the recruiter side plus their chat
  /// messages, job postings, swipes) and removes the Firebase Auth record.
  ///
  /// Does NOT delete the Cloudinary-hosted photo/resume/video files this
  /// account uploaded -- that needs a signed server-side call (the API
  /// secret can't live in this app), tracked separately; see
  /// docs/cloudinary-setup.md. Those files become unreferenced but remain
  /// on Cloudinary after this runs.
  Future<void> deleteAccount() async {
    final user = currentUser;
    if (user == null) return;
    await _guard(_api.deleteMe);
    await signOut();
  }
}
