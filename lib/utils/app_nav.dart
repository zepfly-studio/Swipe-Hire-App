import 'package:flutter/foundation.dart';

/// Cross-screen navigation requests (a notification tap, a "Message" button...)
/// that need to switch a bottom-nav tab instead of pushing a new route.
/// The role shells listen to these and reset them to null after handling.
///
/// Recruiter tabs:  0 Swipe, 1 Jobs, 2 Shortlisted, 3 Messages, 4 Interviews.
/// Candidate tabs:  0 Home, 1 Messages, 2 Tasks, 3 Interviews, 4 Profile.
class AppNav {
  AppNav._();

  static const int recruiterSwipe = 0;
  static const int recruiterJobs = 1;
  static const int recruiterShortlisted = 2;
  static const int recruiterMessages = 3;
  static const int recruiterInterviews = 4;

  static const int candidateHome = 0;
  static const int candidateMessages = 1;
  static const int candidateTasks = 2;
  static const int candidateInterviews = 3;
  static const int candidateProfile = 4;

  /// Ask the recruiter shell to show this tab.
  static final ValueNotifier<int?> recruiterTab = ValueNotifier<int?>(null);

  /// Ask the candidate shell to show this tab.
  static final ValueNotifier<int?> candidateTab = ValueNotifier<int?>(null);

  /// A saved-search id the swipe screen should apply (from an alert
  /// notification: "/company/swipe?search=ID"). The swipe screen clears it.
  static final ValueNotifier<String?> swipeSearchId = ValueNotifier<String?>(null);

  /// A user id whose chat thread the Messages tab should open.
  static final ValueNotifier<String?> openChatWith = ValueNotifier<String?>(null);
}
