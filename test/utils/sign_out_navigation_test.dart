import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/utils/sign_out_navigation.dart';

void main() {
  testWidgets('signing out closes every pushed screen and shows the root', (tester) async {
    final key = GlobalKey<NavigatorState>();
    final auth = StreamController<Object?>.broadcast();
    final watch = popToRootOnSignOut(auth.stream, key);
    addTearDown(() async {
      await watch.cancel();
      await auth.close();
    });

    await tester.pumpWidget(MaterialApp(navigatorKey: key, home: const Text('login-or-home')));
    key.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Text('profile')));
    await tester.pumpAndSettle();
    key.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Text('security')));
    await tester.pumpAndSettle();
    expect(find.text('security'), findsOneWidget);

    // Still signed in: nothing closes.
    auth.add(Object());
    await tester.pumpAndSettle();
    expect(find.text('security'), findsOneWidget);

    // Signed out: back to the root screen.
    auth.add(null);
    await tester.pumpAndSettle();
    expect(find.text('security'), findsNothing);
    expect(find.text('profile'), findsNothing);
    expect(find.text('login-or-home'), findsOneWidget);
  });

  testWidgets('a sign-out while only the root is open does nothing', (tester) async {
    final key = GlobalKey<NavigatorState>();
    final auth = StreamController<Object?>.broadcast();
    final watch = popToRootOnSignOut(auth.stream, key);
    addTearDown(() async {
      await watch.cancel();
      await auth.close();
    });

    await tester.pumpWidget(MaterialApp(navigatorKey: key, home: const Text('root')));
    auth.add(null);
    await tester.pumpAndSettle();
    expect(find.text('root'), findsOneWidget);
  });
}
