import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/screens/account/account_security_screen.dart';
import 'package:hiring_app/services/api_client.dart';
import 'package:hiring_app/services/auth_service.dart';
import 'package:hiring_app/theme/app_theme.dart';
import 'package:hiring_app/widgets/app_toast.dart';

import '../helpers/fake_api.dart';

class _SecurityApi extends FakeApi {
  ApiException? changeError;
  final List<({String current, String next})> changes = [];
  int logoutAllCalls = 0;

  @override
  Future<void> changePassword({required String current, required String next}) async {
    changes.add((current: current, next: next));
    if (changeError != null) throw changeError!;
  }

  @override
  Future<void> logoutAll() async => logoutAllCalls++;
}

void main() {
  group('validatePasswordChange', () {
    test('accepts a good form', () {
      expect(validatePasswordChange(current: 'old-pass', next: 'new-password', confirm: 'new-password'), isEmpty);
    });

    test('flags empty current, short new and mismatched confirm', () {
      final errors = validatePasswordChange(current: '', next: 'short', confirm: 'other');
      expect(errors['current'], 'Enter your current password');
      expect(errors['next'], 'New password must be at least 8 characters');
      expect(errors['confirm'], 'Passwords do not match');
    });

    test('exactly 8 characters is enough', () {
      expect(validatePasswordChange(current: 'x', next: '12345678', confirm: '12345678'), isEmpty);
    });
  });

  group('AccountSecurityScreen', () {
    late _SecurityApi api;
    late AuthService auth;

    setUp(() {
      api = _SecurityApi();
      auth = AuthService.test(
        auth: MockFirebaseAuth(mockUser: MockUser(uid: 'u1', email: 'a@b.co'), signedIn: true),
        api: api,
      );
    });

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        builder: AppToastHost.builder,
        home: AccountSecurityScreen(authService: auth),
      ));
      await tester.pump();
    }

    Future<void> fill(WidgetTester tester, String current, String next, String confirm) async {
      await tester.enterText(find.byKey(const Key('field-current')), current);
      await tester.enterText(find.byKey(const Key('field-next')), next);
      await tester.enterText(find.byKey(const Key('field-confirm')), confirm);
      await tester.pump();
    }

    testWidgets('a mismatch is caught on the device and nothing is sent', (tester) async {
      await pump(tester);
      await fill(tester, 'old-pass', 'new-password', 'new-passwor');
      await tester.tap(find.text('Update password'));
      await tester.pump();

      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(api.changes, isEmpty);
    });

    testWidgets('a wrong current password is marked on that field', (tester) async {
      api.changeError = ApiException(
        400,
        'Your current password is not correct',
        body: {'error': 'Your current password is not correct', 'field': 'current'},
      );
      await pump(tester);
      await fill(tester, 'nope', 'new-password', 'new-password');
      await tester.tap(find.text('Update password'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(api.changes.single, (current: 'nope', next: 'new-password'));
      expect(find.text('Your current password is not correct'), findsOneWidget);
    });

    testWidgets('success clears the form and toasts', (tester) async {
      await pump(tester);
      await fill(tester, 'old-pass', 'new-password', 'new-password');
      await tester.tap(find.text('Update password'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(api.changes, hasLength(1));
      expect(find.text('Password changed. Other devices have been logged out.'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('field-current'))).controller!.text, isEmpty);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('log out of all devices asks first, then calls the backend', (tester) async {
      await pump(tester);

      await tester.tap(find.text('Log out of all devices'));
      await tester.pumpAndSettle();
      expect(find.text('Log out of Swipe Hire on all devices, including this one?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(api.logoutAllCalls, 0);

      await tester.tap(find.text('Log out of all devices'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Log out')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(api.logoutAllCalls, 1);
      await tester.pump(const Duration(seconds: 6));
    });
  });
}
