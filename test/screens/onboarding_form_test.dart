import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/models/candidate_profile.dart';
import 'package:hiring_app/screens/candidate/onboarding/onboarding_form.dart';
import 'package:hiring_app/screens/candidate/onboarding/onboarding_media.dart';

OnboardingForm validForm() => OnboardingForm()
  ..phone = '98765 43210'
  ..age = '24'
  ..gender = 'Female'
  ..location = 'Jaipur'
  ..qualification = 'Graduate'
  ..degree = 'B.Tech (CSE)'
  ..desiredRole = 'Web Developer'
  ..skills = ['React']
  ..experience = '0'
  ..expectedMin = '6';

void main() {
  group('step validation', () {
    test('valid form has no errors', () {
      final f = validForm();
      expect(f.validateDetails(), isEmpty);
      expect(f.validateWork(), isEmpty);
    });

    test('details messages', () {
      final e = OnboardingForm().validateDetails();
      expect(e['phone'], 'Enter a valid phone number');
      expect(e['age'], 'Enter your age');
      expect(e['gender'], 'Select your gender');
      expect(e['location'], 'Enter your city');
      expect(e['qualification'], 'Select your qualification');
      expect(e['degree'], 'Enter your degree');
      expect(e.containsKey('graduationYear'), isFalse);

      final f = validForm()
        ..age = '15'
        ..graduationYear = '1800';
      final e2 = f.validateDetails();
      expect(e2['age'], 'Age must be between 16 and 75');
      expect(e2['graduationYear'], 'Enter a year like 2023');
    });

    test('work messages', () {
      final e = OnboardingForm().validateWork();
      expect(e['desiredRole'], 'Enter the role you are looking for');
      expect(e['skills'], 'Add at least one skill');
      expect(e['experience'], 'Enter your experience (0 if fresher)');
      expect(e['expectedSalaryLpa'], 'Enter the minimum salary you expect');

      final f = validForm()
        ..expectedMax = '5'
        ..currentSalary = 'abc';
      final e2 = f.validateWork();
      expect(e2['expectedSalaryMaxLpa'], 'Should be more than the minimum');
      expect(e2['currentSalaryLpa'], 'Enter a valid salary');
    });
  });

  group('profile output', () {
    test('fresher sends "Fresher" and rupee salaries are converted', () {
      final p = (validForm()..expectedMin = '600000').toProfile();
      expect(p.experience, 'Fresher');
      expect(p.expectedSalaryLpa, closeTo(6, 1e-9));
      expect(p.toMap()['desiredRole'], 'Web Developer');
      expect(p.toMap().containsKey('openToWork'), isFalse);
    });

    test('experienced candidate sends "<n> years"', () {
      final p = (validForm()..experience = '3').toProfile();
      expect(p.experience, '3 years');
    });

    test('round trip through a profile', () {
      const base = CandidateProfile(
        age: 30,
        gender: 'Male',
        qualification: 'PhD',
        experience: '5 years',
        expectedSalaryLpa: 12,
        expectedSalaryMaxLpa: 15,
        salaryNegotiable: true,
        noticePeriod: '30 days',
      );
      final f = OnboardingForm.fromProfile(base);
      expect(f.experience, '5');
      expect(f.expectedMin, '12');
      expect(f.negotiable, isTrue);
      final back = f.toProfile(base: base);
      expect(back.experience, '5 years');
      expect(back.expectedSalaryMaxLpa, 15);
    });

    test('draft round trip', () {
      final f = validForm()
        ..skills = ['React', 'Excel']
        ..negotiable = true;
      final g = OnboardingForm()..applyDraft(f.toDraft());
      expect(g.phone, f.phone);
      expect(g.skills, ['React', 'Excel']);
      expect(g.negotiable, isTrue);
    });
  });

  group('resume auto-fill', () {
    test('fills only empty fields and counts them', () {
      final f = OnboardingForm()
        ..phone = '12345 67890'
        ..location = 'Pune';
      final n = f.applyAutofill({
        'phone': '99999 99999',
        'skills': ['react', 'Excel'],
        'degree': 'B.Tech',
        'qualification': 'graduate',
        'graduationYear': 2022,
        'college': 'IIT',
        'desiredRole': 'Developer',
        'location': 'Delhi',
        'experienceYears': 2,
        'currentCompany': 'Acme',
        'currentPost': 'Dev',
      }, skillOptions: ['React']);
      expect(f.phone, '12345 67890');
      expect(f.location, 'Pune');
      expect(f.skills, ['React', 'Excel']);
      expect(f.qualification, 'Graduate');
      expect(f.graduationYear, '2022');
      expect(f.experience, '2');
      expect(n, 9);
    });

    test('nothing found fills nothing', () {
      expect(OnboardingForm().applyAutofill({}), 0);
    });
  });

  group('server field errors', () {
    test('map to the right step', () {
      expect(stepForField('phone'), 0);
      expect(stepForField('age'), 0);
      expect(stepForField('degree'), 0);
      expect(stepForField('desiredRole'), 1);
      expect(stepForField('headline'), 1);
      expect(stepForField('skills'), 1);
      expect(stepForField('expectedSalaryLpa'), 1);
      expect(stepForField('resumeUrl'), 2);
      expect(stepForField('introVideoUrl'), 3);
      expect(canonicalField('experienceYears'), 'experience');
    });
  });

  group('media validation', () {
    test('resume', () {
      expect(validateResumeFile('cv.docx', 100), 'Please choose a PDF file');
      expect(validateResumeFile('cv.pdf', 6 * 1024 * 1024), 'Your PDF must be under 5 MB');
      expect(validateResumeFile('CV.PDF', 1000), isNull);
    });

    test('video', () {
      expect(validateVideoFile('a.avi', 10), 'Please choose an MP4, WebM or MOV video');
      expect(validateVideoFile('a.mp4', 41 * 1024 * 1024), 'Video must be under 40 MB');
      expect(validateVideoFile('a.mov', 1000), isNull);
      expect(validateVideoDuration(null), isNull);
      expect(validateVideoDuration(4.4), 'Your video is 4 seconds. Please upload a 5–15 second video.');
      expect(validateVideoDuration(4.5), isNull);
      expect(validateVideoDuration(15.5), isNull);
      expect(validateVideoDuration(16), isNotNull);
    });
  });
}
