import 'dart:async';

import 'package:flutter/widgets.dart';

/// Whenever the signed-in account goes away (log out, "log out of all
/// devices", an expired session, a removed team member...) every screen that
/// was pushed on top of the root route is closed, so the root (AuthGate)
/// shows the login page. Without this, a Profile or Settings page that was
/// pushed over AuthGate would stay on screen after logging out.
///
/// [authState] emits the current user or null; null means signed out.
StreamSubscription<Object?> popToRootOnSignOut(
  Stream<Object?> authState,
  GlobalKey<NavigatorState> navigatorKey,
) {
  return authState.listen((user) {
    if (user != null) return;
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    navigator.popUntil((route) => route.isFirst);
  });
}
