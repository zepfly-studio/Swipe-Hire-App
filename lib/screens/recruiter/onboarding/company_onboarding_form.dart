import '../../../models/hiring_company.dart';
import '../../../utils/salary.dart';

const List<String> kIndustries = [
  'IT / Software',
  'E-commerce',
  'Finance',
  'Healthcare',
  'Education',
  'Manufacturing',
  'Marketing / Media',
  'Retail',
  'Real Estate',
  'Other',
];

const List<String> kCompanySizes = ['1–10', '11–50', '51–200', '201–1000', '1000+'];

/// "1-10" and "1–10" are the same size; the list uses the en dash.
String canonicalCompanySize(String value) {
  final v = value.trim().replaceAll('-', '–');
  return kCompanySizes.contains(v) ? v : '';
}

const Set<String> _companyFields = {'name', 'location', 'website', 'industry', 'size', 'about', 'companyName'};

/// 0 = "About your company", 1 = "Who are you hiring?" for a server `field`
/// such as `company.name`, `job.salaryMaxLpa` or a bare `website`.
int onboardingStepForField(String field) {
  if (field.startsWith('company.')) return 0;
  if (field.startsWith('job.')) return 1;
  return _companyFields.contains(field) ? 0 : 1;
}

/// The two onboarding steps' answers (raw text) with validation and the
/// POST /company/onboarding body (spec C1).
class CompanyOnboardingForm {
  // Step 1
  String name;
  String industry;
  String size;
  String location;
  String website;
  String about;

  // Step 2
  String role;
  List<String> skills;
  String minExp;
  String maxExp;
  String minSalary;
  String maxSalary;
  String jobLocation;
  String workMode;

  CompanyOnboardingForm({
    this.name = '',
    this.industry = '',
    this.size = '',
    this.location = '',
    this.website = '',
    this.about = '',
    this.role = '',
    List<String>? skills,
    this.minExp = '',
    this.maxExp = '',
    this.minSalary = '',
    this.maxSalary = '',
    this.jobLocation = '',
    this.workMode = 'onsite',
  }) : skills = skills ?? [];

  factory CompanyOnboardingForm.fromCompany(HiringCompany c, {String suggestedName = ''}) => CompanyOnboardingForm(
        name: c.name.isNotEmpty ? c.name : suggestedName,
        industry: kIndustries.contains(c.industry) ? c.industry : '',
        size: canonicalCompanySize(c.size),
        location: c.location,
        website: c.website,
        about: c.about,
      );

  /// Step 1 errors (keys `company.name`, `company.location`).
  Map<String, String> validateCompany() {
    final e = <String, String>{};
    final n = name.trim();
    if (n.isEmpty) {
      e['company.name'] = 'Enter your company name';
    } else if (n.length > 100) {
      e['company.name'] = 'Company name can be up to 100 characters';
    }
    final l = location.trim();
    if (l.isEmpty) {
      e['company.location'] = 'Enter your company location';
    } else if (l.length > 80) {
      e['company.location'] = 'Location can be up to 80 characters';
    }
    return e;
  }

  /// Step 2 errors (keys `job.*`).
  Map<String, String> validateJob() {
    final e = <String, String>{};
    if (role.trim().isEmpty) e['job.title'] = 'Enter the role you are hiring for';
    if (skills.isEmpty) e['job.skills'] = 'Add at least one skill';

    double? minE;
    double? maxE;
    if (minExp.trim().isNotEmpty) {
      minE = parseYears(minExp);
      if (minE == null || minE < 0 || minE > 50) e['job.minExperienceYears'] = 'Enter years between 0 and 50';
    }
    if (maxExp.trim().isNotEmpty) {
      maxE = parseYears(maxExp);
      if (maxE == null || maxE < 0 || maxE > 50) e['job.maxExperienceYears'] = 'Enter years between 0 and 50';
    }
    if (!e.containsKey('job.minExperienceYears') && minE != null && maxE != null && minE > maxE) {
      e['job.minExperienceYears'] = 'Must be less than maximum';
    }

    double? minS;
    double? maxS;
    if (minSalary.trim().isNotEmpty) {
      minS = parseLpa(minSalary).value;
      if (minS == null) e['job.salaryMinLpa'] = 'Enter a valid salary';
    }
    if (maxSalary.trim().isEmpty) {
      e['job.salaryMaxLpa'] = 'Enter the maximum salary you can offer';
    } else {
      maxS = parseLpa(maxSalary).value;
      if (maxS == null || maxS <= 0) e['job.salaryMaxLpa'] = 'Enter a valid salary';
    }
    if (minS != null && maxS != null && minS > maxS && !e.containsKey('job.salaryMinLpa')) {
      e['job.salaryMinLpa'] = 'Must be less than maximum';
    }
    return e;
  }

  Map<String, String> validateAll() => {...validateCompany(), ...validateJob()};

  /// The company fields, as PUT /company/me and onboarding's `company` take them.
  Map<String, dynamic> companyBody() => {
        'name': name.trim(),
        'industry': industry,
        'size': size,
        'location': location.trim(),
        'website': website.trim(),
        'about': about.trim(),
      };

  Map<String, dynamic> jobBody() => {
        'title': role.trim(),
        'skills': skills,
        'minExperienceYears': minExp.trim().isEmpty ? 0 : parseYears(minExp) ?? 0,
        if (maxExp.trim().isNotEmpty) 'maxExperienceYears': parseYears(maxExp),
        if (minSalary.trim().isNotEmpty) 'salaryMinLpa': parseLpa(minSalary).value,
        'salaryMaxLpa': parseLpa(maxSalary).value,
        'location': (jobLocation.trim().isEmpty ? location : jobLocation).trim(),
        'workMode': workMode,
      };

  /// Body of POST /company/onboarding.
  Map<String, dynamic> toRequestBody() => {'company': companyBody(), 'job': jobBody()};
}
