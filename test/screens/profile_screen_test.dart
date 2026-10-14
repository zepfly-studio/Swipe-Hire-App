import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/screens/profile_screen.dart';
import 'package:hiring_app/services/api_client.dart';
import 'package:hiring_app/services/auth_service.dart';
import 'package:hiring_app/services/recruiter_profile_service.dart';
import 'package:hiring_app/theme/app_theme.dart';
import 'package:hiring_app/widgets/app_toast.dart';

import '../helpers/fake_api.dart';

void main() {
  late FakeApi api;
  late AuthService auth;

  setUpAll(() {
    RecruiterProfileService.instance.useInMemoryStorage();
  });

  setUp(() async {
    await RecruiterProfileService.instance.save(
      name: 'Rec One',
      designation: 'HR Manager',
      company: 'Acme',
      email: 'rec@example.com',
      phone: '9876543210',
    );
    api = FakeApi()
      ..account = {
        'uid': 'rec-1',
        'email': 'rec@example.com',
        'name': 'Rec One',
        'role': 'recruiter',
        'company': 'Acme',
        'designation': 'HR Manager',
        'phone': '9876543210',
        'profileComplete': true,
      };
    auth = AuthService.test(
      auth: MockFirebaseAuth(mockUser: MockUser(uid: 'rec-1', email: 'rec@example.com'), signedIn: true),
      api: api,
    );
  });

  Future<void> pumpProfile(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      builder: AppToastHost.builder,
      home: ProfileScreen(authService: auth),
    ));
    await tester.pump(const Duration(milliseconds: 800));
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  /// Lets a toast slide in (the first pump builds it, then it animates).
  Future<void> settleToast(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('a clean profile says all changes are saved', (tester) async {
    await pumpProfile(tester);

    expect(find.text('All changes saved'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('saving a change shows a success toast and the saved chip', (tester) async {
    await pumpProfile(tester);

    await tester.enterText(field('Company'), 'Acme Labs');
    await tester.pump();
    expect(find.text('Unsaved changes'), findsOneWidget);

    await tester.tap(find.text('Save changes'));
    await settleToast(tester);

    expect(api.updateMeCalls, 1);
    expect(api.account!['company'], 'Acme Labs');
    expect(find.text('Profile saved'), findsOneWidget);
    expect(find.text('All changes saved'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a bad phone number is explained in a toast and nothing is sent', (tester) async {
    await pumpProfile(tester);

    await tester.enterText(field('Phone'), 'wdwcde2');
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await settleToast(tester);

    expect(api.updateMeCalls, 0);
    expect(find.text('One detail needs fixing'), findsOneWidget);
    expect(find.text('Phone: Enter a valid phone number (10 digits)'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('saving with no changes says so instead of staying silent', (tester) async {
    await pumpProfile(tester);

    await tester.tap(find.text('Save changes'));
    await settleToast(tester);

    expect(api.updateMeCalls, 0);
    expect(find.text('Nothing to save'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a backend rejection is shown as an error toast with its message', (tester) async {
    api.updateMeError = ApiException(400, 'Enter a valid designation, e.g. HR Manager.');
    await pumpProfile(tester);

    await tester.enterText(field('Company'), 'Acme Labs');
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await settleToast(tester);

    expect(find.text('Could not save your profile'), findsOneWidget);
    expect(find.text('Enter a valid designation, e.g. HR Manager.'), findsOneWidget);
    expect(find.text('Unsaved changes'), findsOneWidget);

    await tester.pump(const Duration(seconds: 7));
  });
}
