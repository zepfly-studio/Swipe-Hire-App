import 'package:flutter/foundation.dart';

import 'auth_service.dart';

/// What the signed-in account is allowed to do beyond its role: staff
/// (`isAdmin`) and company ownership (`isOwner`, false for invited teammates).
class AccountFlags {
  const AccountFlags({required this.uid, this.isAdmin = false, this.isOwner = true});
  final String uid;
  final bool isAdmin;
  final bool isOwner;
}

/// Loads [AccountFlags] once the company shell opens, so menus and the company
/// profile can adapt without every screen being handed the user.
class AccountFlagsService {
  AccountFlagsService._();

  static final ValueNotifier<AccountFlags?> current = ValueNotifier<AccountFlags?>(null);

  /// The flags of the account signed in right now, or null while unknown
  /// (never another user's flags left over from a previous session).
  static AccountFlags? forCurrentUser({AuthService? auth}) {
    try {
      final flags = current.value;
      if (flags == null) return null;
      final uid = (auth ?? AuthService.instance).currentUid;
      return flags.uid == uid ? flags : null;
    } catch (_) {
      return null;
    }
  }

  /// Re-reads the profile (GET /users/me). Failures are ignored: the flags
  /// stay unknown and the UI keeps its safe defaults (no Admin entry).
  static Future<void> refresh({AuthService? auth}) async {
    try {
      final service = auth ?? AuthService.instance;
      final uid = service.currentUid;
      if (uid.isEmpty) return;
      final profile = await service.fetchProfile(uid);
      if (profile == null) return;
      current.value = AccountFlags(uid: profile.uid, isAdmin: profile.isAdmin, isOwner: profile.isOwner);
    } catch (_) {}
  }
}
