import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../../../models/candidate_profile.dart';
import '../../../utils/salary.dart';
import '../../../utils/tag_list.dart';

const List<String> kGenders = ['Male', 'Female', 'Other'];
const List<String> kQualifications = [
  '10th',
  '12th',
  'Diploma',
  'Graduate',
  'Post Graduate',
  'PhD',
];
const List<String> kNoticePeriods = [
  'Immediate',
  '15 days',
  '30 days',
  '60 days',
  '90 days',
];
const List<String> kWorkModes = ['onsite', 'hybrid', 'remote'];
const Map<String, String> kWorkModeLabels = {
  'onsite': 'On-site',
  'hybrid': 'Hybrid',
  'remote': 'Remote',
};
const List<String> kJobTypes = [
  'full-time',
  'part-time',
  'internship',
  'contract',
];
const Map<String, String> kJobTypeLabels = {
  'full-time': 'Full-time',
  'part-time': 'Part-time',
  'internship': 'Internship',
  'contract': 'Contract',
};

/// Step titles/subtitles, exactly as on the website.
const List<(String, String)> kStepTexts = [
  ('Tell us about yourself', 'Basic and education details'),
  ('Your work & skills', 'This is what companies match you on'),
  ('Upload your resume', 'Companies double-tap your card to read it'),
  (
    'Record a quick intro',
    '5–15 seconds: your name, your role and what makes you great',
  ),
];

final RegExp _phoneRe = RegExp(r'^[+\d][\d\s-]{8,15}$');

/// Server `field` names that differ from the ones this form uses.
const Map<String, String> _fieldAliases = {
  'headline': 'desiredRole',
  'role': 'desiredRole',
  'jobTitle': 'desiredRole',
  'title': 'desiredRole',
  'experienceYears': 'experience',
  'currentSalary': 'currentSalaryLpa',
  'expectedSalary': 'expectedSalaryLpa',
  'expectedSalaryMin': 'expectedSalaryLpa',
  'expectedSalaryMax': 'expectedSalaryMaxLpa',
  'videoUrl': 'introVideoUrl',
  'video': 'introVideoUrl',
  'resume': 'resumeUrl',
};

const Set<String> _step0Fields = {
  'phone',
  'age',
  'gender',
  'location',
  'qualification',
  'degree',
  'college',
  'graduationYear',
};

/// Normalises a server error `field` to this form's key.
String canonicalField(String field) => _fieldAliases[field] ?? field;

/// The wizard step a (canonical) field lives on.
int stepForField(String field) {
  final f = canonicalField(field);
  if (_step0Fields.contains(f)) return 0;
  if (f == 'resumeUrl') return 2;
  if (f == 'introVideoUrl') return 3;
  return 1;
}

/// Everything the candidate types on steps 0-1, kept as the raw text the
/// inputs show. Validation and the PUT body are derived from it, and steps
/// 0-1 are saved locally as a draft so leaving the screen keeps answers.
class OnboardingForm {
  // Step 0
  String phone = '';
  String age = '';
  String gender = '';
  String location = '';
  String qualification = '';
  String degree = '';
  String college = '';
  String graduationYear = '';

  // Step 1
  String desiredRole = '';
  List<String> skills = [];
  String experience = ''; // years, as typed
  String noticePeriod = '';
  String currentCompany = '';
  String currentPost = '';
  String currentSalary = '';
  String expectedMin = '';
  String expectedMax = '';
  bool negotiable = false;
  List<String> workModes = [];
  List<String> jobTypes = [];
  String about = '';

  OnboardingForm();

  factory OnboardingForm.fromProfile(CandidateProfile p) {
    String num(double v) => v <= 0
        ? ''
        : (v == v.roundToDouble() ? v.round().toString() : v.toString());
    final f = OnboardingForm()
      ..phone = p.phone
      ..age = p.age > 0 ? p.age.toString() : ''
      ..gender = kGenders.contains(p.gender) ? p.gender : ''
      ..location = p.location
      ..qualification = kQualifications.contains(p.qualification)
          ? p.qualification
          : ''
      ..degree = p.degree
      ..college = p.college
      ..graduationYear = p.graduationYear > 0 ? p.graduationYear.toString() : ''
      ..desiredRole = p.desiredRole
      ..skills = [...p.skills]
      ..noticePeriod = kNoticePeriods.contains(p.noticePeriod)
          ? p.noticePeriod
          : ''
      ..currentCompany = p.currentCompany
      ..currentPost = p.currentPost
      ..currentSalary = num(p.currentSalaryLpa)
      ..expectedMin = num(p.expectedSalaryLpa)
      ..expectedMax = num(p.expectedSalaryMaxLpa)
      ..negotiable = p.salaryNegotiable
      ..workModes = [...p.workModes]
      ..jobTypes = [...p.jobTypes]
      ..about = p.about;
    // "0" must show for a fresher; only an unset experience stays empty.
    if (p.experience.trim().isNotEmpty) {
      final years = p.experienceYears;
      f.experience = years == years.roundToDouble()
          ? years.round().toString()
          : years.toString();
    }
    return f;
  }

  Map<String, dynamic> toDraft() => {
    'phone': phone,
    'age': age,
    'gender': gender,
    'location': location,
    'qualification': qualification,
    'degree': degree,
    'college': college,
    'graduationYear': graduationYear,
    'desiredRole': desiredRole,
    'skills': skills,
    'experience': experience,
    'noticePeriod': noticePeriod,
    'currentCompany': currentCompany,
    'currentPost': currentPost,
    'currentSalary': currentSalary,
    'expectedMin': expectedMin,
    'expectedMax': expectedMax,
    'negotiable': negotiable,
    'workModes': workModes,
    'jobTypes': jobTypes,
    'about': about,
  };

  /// Draft values overwrite the profile's.
  void applyDraft(Map<String, dynamic> d) {
    String s(String k, String cur) => d[k] is String ? d[k] as String : cur;
    List<String> l(String k, List<String> cur) =>
        d[k] is List ? [for (final e in d[k] as List) e.toString()] : cur;
    phone = s('phone', phone);
    age = s('age', age);
    gender = s('gender', gender);
    location = s('location', location);
    qualification = s('qualification', qualification);
    degree = s('degree', degree);
    college = s('college', college);
    graduationYear = s('graduationYear', graduationYear);
    desiredRole = s('desiredRole', desiredRole);
    skills = l('skills', skills);
    experience = s('experience', experience);
    noticePeriod = s('noticePeriod', noticePeriod);
    currentCompany = s('currentCompany', currentCompany);
    currentPost = s('currentPost', currentPost);
    currentSalary = s('currentSalary', currentSalary);
    expectedMin = s('expectedMin', expectedMin);
    expectedMax = s('expectedMax', expectedMax);
    negotiable = d['negotiable'] is bool ? d['negotiable'] as bool : negotiable;
    workModes = l('workModes', workModes);
    jobTypes = l('jobTypes', jobTypes);
    about = s('about', about);
  }

  // -- resume auto-fill -----------------------------------------------------

  /// Fills only EMPTY fields from the resume reader's answer and returns how
  /// many fields it filled. [skillOptions] gives skills the list's spelling.
  int applyAutofill(
    Map<String, dynamic> f, {
    List<String> skillOptions = const [],
  }) {
    var filled = 0;
    String text(String k) => f[k] == null ? '' : f[k].toString().trim();

    void fill(String key, String current, void Function(String) set) {
      final v = text(key);
      if (current.trim().isEmpty && v.isNotEmpty) {
        set(v);
        filled++;
      }
    }

    fill('phone', phone, (v) => phone = v);
    fill('degree', degree, (v) => degree = v);
    fill('college', college, (v) => college = v);
    fill('desiredRole', desiredRole, (v) => desiredRole = v);
    fill('location', location, (v) => location = v);
    fill('currentCompany', currentCompany, (v) => currentCompany = v);
    fill('currentPost', currentPost, (v) => currentPost = v);

    final q = text('qualification').toLowerCase();
    if (qualification.isEmpty && q.isNotEmpty) {
      final match = kQualifications.where((o) => o.toLowerCase() == q);
      if (match.isNotEmpty) {
        qualification = match.first;
        filled++;
      }
    }

    final year = int.tryParse(text('graduationYear'));
    if (graduationYear.trim().isEmpty &&
        year != null &&
        year >= 1960 &&
        year <= 2040) {
      graduationYear = year.toString();
      filled++;
    }

    final exp = double.tryParse(text('experienceYears'));
    if (experience.trim().isEmpty && exp != null && exp >= 0 && exp <= 50) {
      experience = exp == exp.roundToDouble()
          ? exp.round().toString()
          : exp.toString();
      filled++;
    }

    if (skills.isEmpty && f['skills'] is List) {
      var next = <String>[];
      for (final s in (f['skills'] as List).take(15)) {
        next = addTag(next, s.toString(), options: skillOptions);
      }
      if (next.isNotEmpty) {
        skills = next;
        filled++;
      }
    }
    return filled;
  }

  // -- validation -----------------------------------------------------------

  /// Errors for step 0, keyed by field name. Empty map = valid.
  Map<String, String> validateDetails() {
    final e = <String, String>{};
    if (!_phoneRe.hasMatch(phone.trim())) {
      e['phone'] = 'Enter a valid phone number';
    }
    final a = int.tryParse(age.trim());
    if (age.trim().isEmpty) {
      e['age'] = 'Enter your age';
    } else if (a == null || a < 16 || a > 75) {
      e['age'] = 'Age must be between 16 and 75';
    }
    if (gender.isEmpty) e['gender'] = 'Select your gender';
    if (location.trim().isEmpty) e['location'] = 'Enter your city';
    if (qualification.isEmpty) e['qualification'] = 'Select your qualification';
    if (degree.trim().isEmpty) e['degree'] = 'Enter your degree';
    if (graduationYear.trim().isNotEmpty) {
      final y = int.tryParse(graduationYear.trim());
      if (y == null || y < 1960 || y > 2040) {
        e['graduationYear'] = 'Enter a year like 2023';
      }
    }
    return e;
  }

  /// Errors for step 1, keyed by field name. Empty map = valid.
  Map<String, String> validateWork() {
    final e = <String, String>{};
    if (desiredRole.trim().isEmpty) {
      e['desiredRole'] = 'Enter the role you are looking for';
    }
    if (skills.isEmpty) e['skills'] = 'Add at least one skill';
    final exp = validateExperienceYears(experience);
    if (exp != null) e['experience'] = exp;
    final cur = validateCurrentSalary(currentSalary);
    if (cur != null) e['currentSalaryLpa'] = cur;
    final min = validateMinSalary(expectedMin);
    if (min != null) e['expectedSalaryLpa'] = min;
    final max = validateMaxSalary(expectedMax, expectedMin);
    if (max != null) e['expectedSalaryMaxLpa'] = max;
    return e;
  }

  // -- output ---------------------------------------------------------------

  /// The profile to PUT. [base] carries what this form does not edit
  /// (photo, resume, video URLs, preferences); the URL arguments override it.
  CandidateProfile toProfile({
    CandidateProfile? base,
    String? resumeUrl,
    String? introVideoUrl,
    String? photoUrl,
  }) {
    final years = parseYears(experience) ?? 0;
    final b = base ?? const CandidateProfile();
    return CandidateProfile(
      age: int.tryParse(age.trim()) ?? 0,
      gender: gender,
      qualification: qualification,
      degree: degree.trim(),
      college: college.trim(),
      graduationYear: int.tryParse(graduationYear.trim()) ?? 0,
      experience: experienceTextFor(years),
      desiredRole: desiredRole.trim(),
      location: location.trim(),
      skills: skills,
      currentCompany: currentCompany.trim(),
      currentPost: currentPost.trim(),
      currentSalaryLpa: parseLpa(currentSalary).value ?? 0,
      expectedSalaryLpa: parseLpa(expectedMin).value ?? 0,
      expectedSalaryMaxLpa: parseLpa(expectedMax).value ?? 0,
      salaryNegotiable: negotiable,
      noticePeriod: noticePeriod,
      workModes: workModes,
      jobTypes: jobTypes,
      about: about.trim(),
      phone: phone.trim(),
      photoUrl: photoUrl ?? b.photoUrl,
      resumeUrl: resumeUrl ?? b.resumeUrl,
      introVideoUrl: introVideoUrl ?? b.introVideoUrl,
      openToWork: b.openToWork,
      preferredLocations: b.preferredLocations,
      activeAt: b.activeAt,
    );
  }
}

/// Local copy of the steps 0-1 answers, per signed-in user (and per
/// create/edit mode), in Hive. Falls back to memory when Hive isn't open.
class OnboardingDraftStore {
  OnboardingDraftStore._();

  static const _boxName = 'candidate_onboarding_drafts';
  static final Map<String, String> _memory = {};

  static String _key(String uid, bool edit) =>
      'draft_$uid${edit ? '_edit' : ''}';

  static Future<Map<String, dynamic>?> load(
    String uid, {
    required bool edit,
  }) async {
    final key = _key(uid, edit);
    String? raw = _memory[key];
    try {
      final box = await Hive.openBox(_boxName);
      raw = box.get(key) as String? ?? raw;
    } catch (_) {}
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(
    String uid,
    Map<String, dynamic> draft, {
    required bool edit,
  }) async {
    final key = _key(uid, edit);
    final raw = jsonEncode(draft);
    _memory[key] = raw;
    try {
      final box = await Hive.openBox(_boxName);
      await box.put(key, raw);
    } catch (_) {}
  }

  static Future<void> clear(String uid) async {
    for (final edit in [false, true]) {
      final key = _key(uid, edit);
      _memory.remove(key);
      try {
        final box = await Hive.openBox(_boxName);
        await box.delete(key);
      } catch (_) {}
    }
  }
}
