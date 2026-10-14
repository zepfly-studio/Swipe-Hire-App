import 'package:flutter/material.dart';
import 'legal_scaffold.dart';

/// Placeholders in ALL CAPS below ([COMPANY_LEGAL_NAME], [SUPPORT_EMAIL],
/// [JURISDICTION]) must be filled in with the real business details before
/// shipping -- see docs/legal-placeholders.md.
class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalScaffold(
      title: 'Terms of Service',
      lastUpdated: '[FILL IN BEFORE LAUNCH]',
      sections: [
        LegalSection(
          '1. Acceptance',
          'By creating an account on SwipeHire ("the App"), operated by '
              '[COMPANY_LEGAL_NAME], you agree to these Terms and to our '
              'Privacy Policy. If you do not agree, do not use the App.',
        ),
        LegalSection(
          '2. Who can use the App',
          'You must be at least 18 years old and able to form a binding '
              'contract to create an account, as either a candidate seeking '
              'employment opportunities or a recruiter posting job openings.',
        ),
        LegalSection(
          '3. Accurate information',
          'You agree that the information you provide -- your profile, resume, '
              'job postings, skills, experience, salary expectations -- is '
              'accurate and not misleading. Posting fraudulent job listings or '
              'fabricated candidate profiles is prohibited and may result in '
              'account removal.',
        ),
        LegalSection(
          '4. Conduct',
          'You agree not to: post unlawful, discriminatory, or deceptive job '
              'listings; harass another user; upload malicious files; attempt '
              'to circumvent the App\'s security or abuse its infrastructure '
              '(e.g. scraping, automated mass applications, upload abuse). We '
              'may suspend or delete accounts that violate this.',
        ),
        LegalSection(
          '5. Content you submit',
          'You retain ownership of the content you upload (resume, photo, '
              'intro video, job descriptions), but grant us a license to store '
              'and display it within the App to the other party it\'s '
              'intended for (recruiters for candidate content, candidates for '
              'job postings) for as long as your account exists.',
        ),
        LegalSection(
          '6. No guarantee of outcome',
          'The App is a platform connecting candidates and recruiters. We do '
              'not guarantee that any candidate will be hired or that any job '
              'posting will be filled, and we are not a party to any '
              'employment relationship or agreement formed between users.',
        ),
        LegalSection(
          '7. Termination',
          'You may delete your account at any time from Profile → Delete '
              'account. We may suspend or terminate accounts that violate '
              'these Terms, at our discretion.',
        ),
        LegalSection(
          '8. Liability',
          'The App is provided "as is". To the extent permitted by law, '
              '[COMPANY_LEGAL_NAME] is not liable for indirect damages arising '
              'from use of the App, including hiring decisions made by users.',
        ),
        LegalSection(
          '9. Governing law',
          'These Terms are governed by the laws of [JURISDICTION]. Contact us '
              'at [SUPPORT_EMAIL] with any questions.',
        ),
      ],
    );
  }
}
