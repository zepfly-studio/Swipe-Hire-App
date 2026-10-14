import 'package:firebase_analytics/firebase_analytics.dart';

/// Thin wrapper over Firebase Analytics for the handful of events worth
/// tracking funnel/retention on: signup completion, job applications,
/// job postings created, and recruiter swipe actions on the candidate
/// deck. Firebase Analytics (unlike Crashlytics) supports web, so no
/// [kIsWeb] guard is needed here.
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  Future<void> logSignUp({required String role}) {
    return _analytics.logSignUp(signUpMethod: role);
  }

  Future<void> logLogin({required String role}) {
    return _analytics.logLogin(loginMethod: role);
  }

  Future<void> logJobApply({required String jobPostingId, required String companyName}) {
    return _analytics.logEvent(
      name: 'job_apply',
      parameters: {'job_posting_id': jobPostingId, 'company_name': companyName},
    );
  }

  Future<void> logJobPosted({required String jobPostingId}) {
    return _analytics.logEvent(name: 'job_posted', parameters: {'job_posting_id': jobPostingId});
  }

  /// [action] is one of 'pass' or 'wishlist' -- what a recruiter did with a
  /// candidate card on the swipe deck.
  Future<void> logCandidateSwipe({required String action}) {
    return _analytics.logEvent(name: 'candidate_swipe', parameters: {'action': action});
  }

  Future<void> setUserRole(String role) {
    return _analytics.setUserProperty(name: 'role', value: role);
  }
}
