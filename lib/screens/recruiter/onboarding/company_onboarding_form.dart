import '../../../models/hiring_company.dart';

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

/// The company onboarding answers (raw text) with validation and the
/// POST /company/onboarding body. There is no job step: recruiters filter
/// candidates instead of posting a job.
class CompanyOnboardingForm {
  String name;
  String industry;
  String size;
  String location;
  String website;
  String about;

  CompanyOnboardingForm({
    this.name = '',
    this.industry = '',
    this.size = '',
    this.location = '',
    this.website = '',
    this.about = '',
  });

  factory CompanyOnboardingForm.fromCompany(HiringCompany c, {String suggestedName = ''}) => CompanyOnboardingForm(
        name: c.name.isNotEmpty ? c.name : suggestedName,
        industry: kIndustries.contains(c.industry) ? c.industry : '',
        size: canonicalCompanySize(c.size),
        location: c.location,
        website: c.website,
        about: c.about,
      );

  /// Errors by key: `company.name`, `company.location`.
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

  /// The company fields, as PUT /company/me and onboarding's `company` take them.
  Map<String, dynamic> companyBody() => {
        'name': name.trim(),
        'industry': industry,
        'size': size,
        'location': location.trim(),
        'website': website.trim(),
        'about': about.trim(),
      };

  /// Body of POST /company/onboarding.
  Map<String, dynamic> toRequestBody() => {'company': companyBody()};
}
