import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/screens/recruiter/verify/verify_company_screen.dart';
import 'package:hiring_app/services/api_client.dart';
import 'package:hiring_app/services/verification_service.dart';
import 'package:hiring_app/theme/app_theme.dart';
import 'package:hiring_app/widgets/app_toast.dart';

class _Api extends ApiClient {
  _Api() : super.forTest();

  Map<String, dynamic> status = {
    'verification': {'status': 'none', 'method': ''},
    'gstin': '',
    'website': 'acme.com',
    'email': 'hr@acme.com',
  };
  Map<String, dynamic> sendAnswer = {'sentTo': 'hr@acme.com'};
  ApiException? sendError;
  ApiException? confirmError;
  final List<String> calls = [];
  final List<Map<String, dynamic>?> bodies = [];

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) async {
    calls.add('GET $path');
    return status;
  }

  @override
  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body}) async {
    calls.add('POST $path');
    bodies.add(body);
    switch (path) {
      case '/company/verification/email/send':
        if (sendError != null) throw sendError!;
        return sendAnswer;
      case '/company/verification/email/confirm':
        if (confirmError != null) throw confirmError!;
        return {
          'verification': {'status': 'verified', 'method': 'email', 'verifiedAt': '2026-10-15T10:00:00Z'},
        };
      case '/company/verification/gst':
        return {
          'verification': {'status': 'pending', 'method': 'gst'},
        };
    }
    return const {};
  }
}

void main() {
  late _Api api;
  var refreshed = 0;

  setUp(() {
    api = _Api();
    refreshed = 0;
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      builder: AppToastHost.builder,
      home: VerifyCompanyScreen(
        service: VerificationService.test(api),
        refreshCompany: () async => refreshed++,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  FilledButton filled(WidgetTester tester, String label) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));

  Future<void> drainToasts(WidgetTester tester) => tester.pump(const Duration(seconds: 7));

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('shows both methods and explains the email rule', (tester) async {
    await pump(tester);

    expect(find.text('Get verified'), findsWidgets);
    expect(find.text('Verify with work email · instant'), findsOneWidget);
    expect(find.text('Verify with GSTIN · reviewed by our team'), findsOneWidget);
    expect(find.textContaining('hr@acme.com'), findsOneWidget);
    expect(find.textContaining('acme.com)'), findsOneWidget);
    expect(find.text('Send code to my email'), findsOneWidget);
  });

  testWidgets('Verify stays disabled until six digits; devCode banner and server error are shown', (tester) async {
    api.sendAnswer = {'sentTo': 'hr@acme.com', 'devCode': '482913'};
    api.confirmError = ApiException(400, 'Wrong code, please check and try again');
    await pump(tester);

    await tester.tap(find.text('Send code to my email'));
    await settle(tester);

    expect(api.calls, contains('POST /company/verification/email/send'));
    expect(find.text('Testing mode: your code is 482913'), findsOneWidget);
    expect(filled(tester, 'Verify').onPressed, isNull);

    final field = find.byKey(const Key('email-code-field'));
    await tester.enterText(field, '12ab3');
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '123');
    expect(filled(tester, 'Verify').onPressed, isNull);

    await tester.enterText(field, '1234567');
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '123456');
    expect(filled(tester, 'Verify').onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
    await settle(tester);
    expect(api.bodies.last, {'code': '123456'});
    expect(find.text('Wrong code, please check and try again'), findsOneWidget);
    await drainToasts(tester);
  });

  testWidgets('a refused send shows the server text under the button', (tester) async {
    api.sendError = ApiException(
      400,
      'Your login email is a personal email. Use GST verification, or sign up with your work email.',
    );
    await pump(tester);

    await tester.tap(find.text('Send code to my email'));
    await settle(tester);

    expect(
      find.text('Your login email is a personal email. Use GST verification, or sign up with your work email.'),
      findsOneWidget,
    );
    expect(find.text('Resend'), findsNothing);
  });

  testWidgets('a correct code replaces the page with the verified card and refreshes the company', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Send code to my email'));
    await settle(tester);

    await tester.enterText(find.byKey(const Key('email-code-field')), '654321');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
    await settle(tester);

    expect(find.byKey(const Key('verified-card')), findsOneWidget);
    expect(find.textContaining('verified by work email'), findsOneWidget);
    expect(refreshed, 1);
    await drainToasts(tester);
  });

  testWidgets('GSTIN: upper-cased, spaces removed, capped at 15, Submit opens at 15', (tester) async {
    await pump(tester);

    final field = find.byKey(const Key('gstin-field'));
    expect(filled(tester, 'Submit').onPressed, isNull);

    await tester.enterText(field, '22aaaaa 0000a1z');
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '22AAAAA0000A1Z');
    expect(filled(tester, 'Submit').onPressed, isNull);

    await tester.enterText(field, '22aaaaa0000a1z5extra');
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '22AAAAA0000A1Z5');
    expect(filled(tester, 'Submit').onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
    await settle(tester);
    expect(api.bodies.last, {'gstin': '22AAAAA0000A1Z5'});
    // Now pending, so the button reads Update.
    expect(find.widgetWithText(FilledButton, 'Update'), findsOneWidget);
    await drainToasts(tester);
  });

  testWidgets('a malformed 15-character GSTIN is explained and not sent', (tester) async {
    await pump(tester);

    await tester.enterText(find.byKey(const Key('gstin-field')), 'ABCDEFGHIJKLMNO');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
    await tester.pump();

    expect(find.text('Please enter a valid 15-character GSTIN'), findsOneWidget);
    expect(api.calls.where((c) => c.contains('/gst')), isEmpty);
  });

  testWidgets('pending status shows the amber banner and an Update button', (tester) async {
    api.status = {
      'verification': {'status': 'pending', 'method': 'gst'},
      'gstin': '22AAAAA0000A1Z5',
      'website': 'acme.com',
      'email': 'hr@acme.com',
    };
    await pump(tester);
    expect(
      find.text(
        'GSTIN 22AAAAA0000A1Z5 is under review. You will get a notification once it is approved, '
        'usually within one working day.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Update'), findsOneWidget);
  });

  testWidgets('rejected status shows the red banner', (tester) async {
    api.status = {
      'verification': {'status': 'rejected', 'method': 'gst'},
      'gstin': '22AAAAA0000A1Z5',
      'website': 'acme.com',
      'email': 'hr@acme.com',
    };
    await pump(tester);
    expect(
      find.text('We could not verify your GSTIN. Please check it, or verify with your work email instead.'),
      findsOneWidget,
    );
  });

  testWidgets('verified by GSTIN says so and hides the methods', (tester) async {
    api.status = {
      'verification': {'status': 'verified', 'method': 'gst', 'verifiedAt': '2026-10-15T10:00:00Z'},
      'gstin': '22AAAAA0000A1Z5',
      'website': 'acme.com',
      'email': 'hr@acme.com',
    };
    await pump(tester);
    expect(find.textContaining('(verified by GSTIN)'), findsOneWidget);
    expect(find.text('Send code to my email'), findsNothing);
  });
}
