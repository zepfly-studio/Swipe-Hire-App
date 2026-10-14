import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/screens/auth/signup_screen.dart';
import 'package:hiring_app/screens/legal/privacy_policy_screen.dart';
import 'package:hiring_app/screens/legal/terms_of_service_screen.dart';
import 'package:hiring_app/theme/app_theme.dart';
import 'package:hiring_app/widgets/app_toast.dart';

void main() {
  Future<void> fillValidForm(WidgetTester tester) async {
    await tester.enterText(find.widgetWithText(TextFormField, 'Full name'), 'Riya Shah');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'riya@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'password123');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), 'password123');
  }

  /// The "Terms of Service"/"Privacy Policy" links are [TextSpan]s inside
  /// one [RichText] (so the sentence wraps as a paragraph), not standalone
  /// [Text] widgets -- so they aren't reachable via `find.text()` +
  /// `tester.tap()`. Walks the span tree to find the one whose text matches
  /// and invokes its recognizer directly, same effect as a real tap on it.
  void tapLinkSpan(WidgetTester tester, String linkText) {
    final richText = tester.widget<RichText>(find.byKey(const Key('signup_terms_richtext')));
    final root = richText.text as TextSpan;
    TapGestureRecognizer? found;
    root.visitChildren((span) {
      if (span is TextSpan && span.text == linkText) {
        found = span.recognizer as TapGestureRecognizer?;
        return false;
      }
      return true;
    });
    expect(found, isNotNull, reason: 'No "$linkText" span with a tap recognizer found');
    found!.onTap!();
  }

  testWidgets('submitting without agreeing to Terms & Privacy shows a message and does not proceed',
      (tester) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, builder: AppToastHost.builder, home: const SignupScreen()));
    // Flush every FadeInUp widget's staggered Future.delayed reveal timer
    // before interacting -- otherwise a timer left pending past this
    // test's end trips flutter_test's "pending timer" teardown check.
    await tester.pump(const Duration(seconds: 1));

    // Default role is recruiter, which also requires a company name.
    await tester.enterText(find.widgetWithText(TextFormField, 'Company name'), 'Acme');
    await fillValidForm(tester);

    final submitButton = find.widgetWithText(FilledButton, 'Create account');
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pump(); // let the SnackBar animate in
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Please agree to the Terms & Privacy Policy to continue.'), findsOneWidget);
  });

  testWidgets('tapping the "Terms of Service" link opens TermsOfServiceScreen', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, builder: AppToastHost.builder, home: const SignupScreen()));

    tapLinkSpan(tester, 'Terms of Service');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(TermsOfServiceScreen), findsOneWidget);
  });

  testWidgets('tapping the "Privacy Policy" link opens PrivacyPolicyScreen', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, builder: AppToastHost.builder, home: const SignupScreen()));

    tapLinkSpan(tester, 'Privacy Policy');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
  });
}
