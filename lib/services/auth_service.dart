import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/app_user.dart';
import 'error_reporter.dart';

/// Wraps Firebase Auth (email/password) together with the `users/{uid}`
/// Firestore profile that records which of the two account types --
/// recruiter or candidate -- a signed-in user is.
class AuthService {
  AuthService._internal();
  static final AuthService instance = AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final CollectionReference<Map<String, dynamic>> _users =
      FirebaseFirestore.instance.collection('users');

  /// Backed by [FirebaseAuth.userChanges] rather than [FirebaseAuth.authStateChanges]
  /// so that [reloadUser] (called after the user confirms their email) emits
  /// a fresh [User] with the updated `emailVerified` flag -- `authStateChanges`
  /// only fires on sign-in/out and would never notice that change.
  Stream<User?> get authStateChanges => _auth.userChanges();
  User? get currentUser => _auth.currentUser;

  Future<AppUser?> fetchProfile(String uid) async {
    final doc = await _users.doc(uid).get();
    if (!doc.exists || doc.data() == null) return null;
    return AppUser.fromMap(uid, doc.data()!);
  }

  /// Same as [fetchProfile], but retries briefly before giving up. Right
  /// after [signUp] creates the Firebase Auth user, [AuthGate]'s listener
  /// fires and tries to read the profile before our own `users/{uid}`
  /// write (a few lines later in the same call) has landed -- without
  /// this grace window AuthGate would treat that in-flight signup as a
  /// stale/corrupt account and sign it back out mid-signup.
  Future<AppUser?> fetchProfileWithRetry(
    String uid, {
    int attempts = 6,
    Duration gap = const Duration(milliseconds: 350),
  }) async {
    for (var i = 0; i < attempts; i++) {
      final profile = await fetchProfile(uid);
      if (profile != null) return profile;
      if (i < attempts - 1) await Future.delayed(gap);
    }
    return null;
  }

  Future<AppUser> signUp({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String company = '',
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user!;
    await user.updateDisplayName(name.trim());
    try {
      await user.sendEmailVerification();
    } catch (e, stackTrace) {
      // Non-critical -- the user can resend from VerifyEmailScreen, so a
      // flaky send here shouldn't block account creation.
      ErrorReporter.report(e, stackTrace, reason: 'signUp: sendEmailVerification failed');
    }

    final profile = AppUser(
      uid: user.uid,
      email: email.trim(),
      name: name.trim(),
      role: role,
      company: company.trim(),
    );
    await _users.doc(user.uid).set({
      ...profile.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return profile;
  }

  Future<AppUser> signIn({required String email, required String password}) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final profile = await fetchProfile(credential.user!.uid);
    if (profile == null) {
      throw FirebaseAuthException(
        code: 'profile-missing',
        message: 'No account profile found for this user.',
      );
    }
    return profile;
  }

  Future<void> sendPasswordReset(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  /// Re-sends the verification link to the signed-in user's own email --
  /// used by [VerifyEmailScreen]'s "Resend" action.
  Future<void> resendVerificationEmail() {
    final user = currentUser;
    if (user == null) return Future.value();
    return user.sendEmailVerification();
  }

  /// Refreshes the signed-in user's token/profile from the server (picks
  /// up `emailVerified` after the link is clicked) and re-emits on
  /// [authStateChanges] so [AuthGate] reacts without a manual navigation.
  Future<void> reloadUser() async {
    await currentUser?.reload();
  }

  /// Saves the remaining recruiter details collected on
  /// [CompleteProfileScreen] and marks the account ready for [RootShell].
  Future<void> completeRecruiterProfile({
    required String designation,
    required String phone,
  }) {
    final uid = currentUser!.uid;
    return _users.doc(uid).update({
      'designation': designation.trim(),
      'phone': phone.trim(),
      'profileComplete': true,
    });
  }

  /// Marks the account ready for [CandidateRootShell] once
  /// [CandidateProfileService.save] has written the candidate's details.
  Future<void> markCandidateProfileComplete() {
    final uid = currentUser!.uid;
    return _users.doc(uid).update({'profileComplete': true});
  }

  Future<void> signOut() => _auth.signOut();
}
