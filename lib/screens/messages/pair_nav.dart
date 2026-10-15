import 'package:flutter/material.dart';
import '../../models/pair/notification_link.dart';
import '../../utils/app_nav.dart';
import '../recruiter/team/team_screen.dart';
import '../recruiter/verify/verify_company_screen.dart';
import '../tasks/tasks_screen.dart';

/// Cross-tab navigation for the pair features (chat / interviews / tasks),
/// built on [AppNav]: it sets the requested tab, then pops back to the shell
/// so the change is visible.
class PairNav {
  PairNav._();

  static void _toShell(BuildContext context) {
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  /// Open the chat thread with [userId] in the Messages tab.
  static void openChat(BuildContext context, String userId, {required bool isCompany}) {
    if (userId.isNotEmpty) AppNav.openChatWith.value = userId;
    if (isCompany) {
      AppNav.recruiterTab.value = AppNav.recruiterMessages;
    } else {
      AppNav.candidateTab.value = AppNav.candidateMessages;
    }
    _toShell(context);
  }

  static void openInterviews(BuildContext context, {required bool isCompany}) {
    if (isCompany) {
      AppNav.recruiterTab.value = AppNav.recruiterInterviews;
    } else {
      AppNav.candidateTab.value = AppNav.candidateInterviews;
    }
    _toShell(context);
  }

  static void openTasks(BuildContext context, {required bool isCompany}) {
    if (isCompany) {
      final nav = Navigator.of(context);
      nav.popUntil((r) => r.isFirst);
      nav.push(MaterialPageRoute<void>(builder: (_) => const TasksScreen()));
    } else {
      AppNav.candidateTab.value = AppNav.candidateTasks;
      _toShell(context);
    }
  }

  static void openShortlisted(BuildContext context) {
    AppNav.recruiterTab.value = AppNav.recruiterShortlisted;
    _toShell(context);
  }

  static void openSwipe(BuildContext context) {
    AppNav.recruiterTab.value = AppNav.recruiterSwipe;
    _toShell(context);
  }

  /// Opens a company-only [page] over the shell (back goes to the shell).
  static void _openCompanyPage(BuildContext context, Widget page) {
    final nav = Navigator.of(context);
    nav.popUntil((r) => r.isFirst);
    nav.push(MaterialPageRoute<void>(builder: (_) => page));
  }

  /// Routes a notification [target]. Returns false when there is nothing to
  /// open (unknown link, or a company-only link for a candidate).
  static bool openTarget(BuildContext context, NotificationTarget target, {required bool isCompany}) {
    switch (target.kind) {
      case NotificationTargetKind.messages:
        openChat(context, target.param ?? '', isCompany: isCompany);
        return true;
      case NotificationTargetKind.interviews:
        openInterviews(context, isCompany: isCompany);
        return true;
      case NotificationTargetKind.tasks:
        openTasks(context, isCompany: isCompany);
        return true;
      case NotificationTargetKind.candidateHome:
        if (isCompany) {
          openSwipe(context);
        } else {
          AppNav.candidateTab.value = AppNav.candidateHome;
          _toShell(context);
        }
        return true;
      case NotificationTargetKind.shortlisted:
        if (isCompany) {
          openShortlisted(context);
        } else {
          AppNav.candidateTab.value = AppNav.candidateHome;
          _toShell(context);
        }
        return true;
      case NotificationTargetKind.swipe:
        if (!isCompany) return false;
        if (target.param != null) AppNav.swipeSearchId.value = target.param;
        openSwipe(context);
        return true;
      case NotificationTargetKind.verify:
        if (!isCompany) return false;
        _openCompanyPage(context, const VerifyCompanyScreen());
        return true;
      case NotificationTargetKind.team:
        if (!isCompany) return false;
        _openCompanyPage(context, const TeamScreen());
        return true;
      case NotificationTargetKind.unknown:
        return false;
    }
  }
}
