import 'package:flutter/material.dart';
import 'legal_scaffold.dart';

/// Placeholders in ALL CAPS below ([COMPANY_LEGAL_NAME], [SUPPORT_EMAIL],
/// [GRIEVANCE_OFFICER_EMAIL], [BUSINESS_ADDRESS]) must be filled in with the
/// real business details before shipping -- see docs/legal-placeholders.md.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalScaffold(
      title: 'Privacy Policy',
      lastUpdated: '[FILL IN BEFORE LAUNCH]',
      sections: [
        LegalSection(
          '1. Who we are',
          'Swipe Hire ("we", "us", "the App") is operated by [COMPANY_LEGAL_NAME]. '
              'This policy explains what personal data we collect from you, why, '
              'and what rights you have over it, in line with India\'s Digital '
              'Personal Data Protection Act, 2023 (DPDP Act).',
        ),
        LegalSection(
          '2. What we collect',
          '• Account data: name, email, password (stored securely by Firebase '
              'Authentication, never in plain text we can read), phone number.\n'
              '• Candidate profile data (if you sign up as a candidate): age, '
              'qualifications, skills, work experience, expected salary, notice '
              'period, and any photo, resume (PDF) or intro video you upload.\n'
              '• Recruiter profile data (if you sign up as a recruiter): company '
              'name, designation, job postings you create.\n'
              '• Usage data: which jobs/candidates you view or act on, so the '
              'relevant features (applications, saved jobs, hiring pipeline) work.\n'
              '• Device/crash data: basic crash and error reports to help us fix '
              'bugs (via Firebase Crashlytics on mobile).',
        ),
        LegalSection(
          '3. Why we collect it (purpose)',
          'We only use your data to run the App: matching candidates with job '
              'postings, letting recruiters review and act on applications, '
              'sending you status notifications about your applications, and '
              'fixing bugs/crashes. We do not sell your personal data.',
        ),
        LegalSection(
          '4. Who can see your data',
          '• A candidate\'s profile, resume, photo and intro video are visible '
              'to recruiter accounts browsing the candidate deck -- that\'s the '
              'core function of the App.\n'
              '• A recruiter\'s job postings are visible to any signed-in '
              'candidate browsing jobs.\n'
              '• We use third-party processors to run the App: Google Firebase '
              '(authentication, database, crash reporting, push notifications) '
              'and Cloudinary (file hosting for photos/resumes/videos). These '
              'providers process data on our behalf under their own security '
              'commitments; we don\'t otherwise share your data with third '
              'parties for marketing purposes.',
        ),
        LegalSection(
          '5. How long we keep it',
          'We keep your data for as long as your account exists. If you delete '
              'your account (Profile → Delete account), we delete your profile, '
              'job postings, and hiring records tied to your account from our '
              'database. Files you uploaded (photo/resume/video) may remain on '
              'our file-hosting provider for a short period after account '
              'deletion before being fully purged.',
        ),
        LegalSection(
          '6. Your rights',
          'You can at any time:\n'
              '• Export a copy of your data (Profile → Export my data).\n'
              '• Correct your profile data directly in the app.\n'
              '• Delete your account and associated data (Profile → Delete '
              'account).\n'
              'You may also contact us at [SUPPORT_EMAIL] to exercise these '
              'rights or ask any question about how your data is handled.',
        ),
        LegalSection(
          '7. Grievance officer',
          'In accordance with the DPDP Act, 2023, grievances regarding your '
              'personal data may be addressed to:\n'
              '[GRIEVANCE_OFFICER_NAME]\n[GRIEVANCE_OFFICER_EMAIL]\n'
              '[BUSINESS_ADDRESS]',
        ),
        LegalSection(
          '8. Changes to this policy',
          'We may update this policy as the App evolves. Material changes will '
              'be reflected with an updated "Last updated" date above.',
        ),
      ],
    );
  }
}
