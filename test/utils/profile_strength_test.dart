import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/models/candidate_profile.dart';
import 'package:hiring_app/utils/profile_strength.dart';

bool _done(CandidateProfile prof, String key) =>
    computeProfileStrength(prof).items.firstWhere((i) => i.key == key).done;

void main() {
  const full = CandidateProfile(
    age: 25,
    experience: '3 years',
    desiredRole: 'Web Developer',
    skills: ['React', 'Node.js', 'SQL', 'CSS', 'HTML'],
    currentCompany: 'Acme',
    currentPost: 'Developer',
    college: 'IIT',
    graduationYear: 2022,
    noticePeriod: '30 days',
    expectedSalaryLpa: 8,
    workModes: ['remote'],
    jobTypes: ['full-time'],
    preferredLocations: ['Jaipur'],
    about: 'I build fast, accessible web applications for the web.',
    resumeUrl: 'https://x/r.pdf',
    introVideoUrl: 'https://x/v.mp4',
  );

  test('weights add up to 100 and a full profile is All-star', () {
    final s = computeProfileStrength(full);
    expect(s.items.fold<int>(0, (a, i) => a + i.points), 100);
    expect(s.score, 100);
    expect(s.level, 'All-star');
    expect(s.missing, isEmpty);
  });

  test('an empty profile only earns the experience-0 points', () {
    final s = computeProfileStrength(const CandidateProfile());
    // experienceYears == 0 counts as "company & role" done (10 points).
    expect(s.score, 10);
    expect(s.level, 'Needs work');
  });

  test('missing items are sorted by points, highest first, max 4 shown', () {
    final s = computeProfileStrength(const CandidateProfile(experience: '4 years'));
    expect(s.score, 0);
    expect(s.topMissing.length, 4);
    expect(s.topMissing.map((i) => i.key), ['video', 'resume', 'skills', 'about']);
  });

  test('level thresholds', () {
    expect(strengthLevel(90), 'All-star');
    expect(strengthLevel(89), 'Strong');
    expect(strengthLevel(70), 'Strong');
    expect(strengthLevel(69), 'Good start');
    expect(strengthLevel(45), 'Good start');
    expect(strengthLevel(44), 'Needs work');
  });

  test('individual rules', () {
    expect(_done(const CandidateProfile(skills: ['a', 'b', 'c', 'd']), 'skills'), isFalse);
    expect(_done(const CandidateProfile(skills: ['a', 'b', 'c', 'd', 'e']), 'skills'), isTrue);
    expect(_done(const CandidateProfile(about: 'short'), 'about'), isFalse);
    expect(_done(CandidateProfile(about: 'x' * 30), 'about'), isTrue);
    expect(_done(const CandidateProfile(experience: '2 years', currentCompany: 'A'), 'company'), isFalse);
    expect(
      _done(const CandidateProfile(experience: '2 years', currentCompany: 'A', currentPost: 'B'), 'company'),
      isTrue,
    );
    expect(_done(const CandidateProfile(experience: 'Fresher'), 'company'), isTrue);
    expect(_done(const CandidateProfile(college: 'X'), 'college'), isFalse);
    expect(_done(const CandidateProfile(college: 'X', graduationYear: 2020), 'college'), isTrue);
    expect(_done(const CandidateProfile(workModes: ['remote']), 'prefs'), isFalse);
    expect(_done(const CandidateProfile(preferredLocations: ['Pune']), 'cities'), isTrue);
  });
}
