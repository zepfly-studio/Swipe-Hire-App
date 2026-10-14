import 'package:firebase_auth/firebase_auth.dart';

/// Translates a [FirebaseAuthException] code into copy a recruiter or
/// candidate can actually act on, instead of showing Firebase's raw message.
String authErrorMessage(FirebaseAuthException e) {
  switch (e.code) {
    case 'invalid-email':
      return 'That email address looks invalid.';
    case 'user-disabled':
      return 'This account has been disabled.';
    case 'user-not-found':
      return 'No account found with that email.';
    case 'wrong-password':
    case 'invalid-credential':
      return 'Incorrect email or password.';
    case 'email-already-in-use':
      return 'An account already exists with that email. Try logging in instead.';
    case 'weak-password':
      return 'Choose a stronger password (at least 8 characters).';
    case 'too-many-requests':
      return 'Too many attempts. Please wait a moment and try again.';
    case 'network-request-failed':
      return 'Network error. Check your connection and try again.';
    case 'profile-missing':
      return 'We could not find your account details. Please sign up again.';
    default:
      return e.message ?? 'Something went wrong. Please try again.';
  }
}
