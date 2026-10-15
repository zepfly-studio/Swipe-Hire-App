import '../../../models/hiring_job.dart';
import '../../../utils/salary.dart';

const List<String> kJobWorkModes = ['onsite', 'hybrid', 'remote'];
const Map<String, String> kJobWorkModeLabels = {'onsite': 'On-site', 'hybrid': 'Hybrid', 'remote': 'Remote'};
const List<String> kJobTypeValues = ['full-time', 'part-time', 'internship', 'contract'];
const Map<String, String> kJobTypeLabelsMap = {
  'full-time': 'Full-time',
  'part-time': 'Part-time',
  'internship': 'Internship',
  'contract': 'Contract',
};

/// Raw text of the job form (JobFormModal, spec C5) with its validation and
/// the request body. Field names in the error map match the server's
/// `field` values (`title`, `skills`, `minExperienceYears`, ...).
class JobForm {
  String title;
  List<String> skills;
  String minExp;
  String maxExp;
  String minSalary;
  String maxSalary;
  String location;
  String openings;
  String workMode;
  String employmentType;
  String description;

  JobForm({
    this.title = '',
    List<String>? skills,
    this.minExp = '',
    this.maxExp = '',
    this.minSalary = '',
    this.maxSalary = '',
    this.location = '',
    this.openings = '1',
    this.workMode = 'onsite',
    this.employmentType = 'full-time',
    this.description = '',
  }) : skills = skills ?? [];

  static String _n(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

  factory JobForm.fromJob(HiringJob j) => JobForm(
        title: j.title,
        skills: [...j.skills],
        minExp: j.minExperienceYears > 0 ? _n(j.minExperienceYears) : '',
        maxExp: j.maxExperienceYears == null ? '' : _n(j.maxExperienceYears!),
        minSalary: j.salaryMinLpa > 0 ? _n(j.salaryMinLpa) : '',
        maxSalary: j.salaryMaxLpa > 0 ? _n(j.salaryMaxLpa) : '',
        location: j.location,
        openings: '${j.openings}',
        workMode: kJobWorkModes.contains(j.workMode) ? j.workMode : 'onsite',
        employmentType: kJobTypeValues.contains(j.employmentType) ? j.employmentType : 'full-time',
        description: j.description,
      );

  /// Field -> message; empty when valid.
  Map<String, String> validate() {
    final e = <String, String>{};
    if (title.trim().isEmpty) {
      e['title'] = 'Enter the role you are hiring for';
    } else if (title.trim().length > 80) {
      e['title'] = 'Keep the job title under 80 characters';
    }
    if (skills.isEmpty) e['skills'] = 'Add at least one skill';

    double? minE;
    double? maxE;
    if (minExp.trim().isNotEmpty) {
      minE = parseYears(minExp);
      if (minE == null || minE < 0 || minE > 50) e['minExperienceYears'] = 'Please enter a valid minimum experience';
    }
    if (maxExp.trim().isNotEmpty) {
      maxE = parseYears(maxExp);
      if (maxE == null || maxE < 0 || maxE > 50) e['maxExperienceYears'] = 'Please enter a valid maximum experience';
    }
    if (!e.containsKey('minExperienceYears') &&
        !e.containsKey('maxExperienceYears') &&
        minE != null &&
        maxE != null &&
        minE > maxE) {
      e['minExperienceYears'] = 'Minimum experience cannot be more than maximum experience';
    }

    double? minS;
    double? maxS;
    if (minSalary.trim().isNotEmpty) {
      minS = parseLpa(minSalary).value;
      if (minS == null) e['salaryMinLpa'] = 'Enter a valid salary';
    }
    if (maxSalary.trim().isEmpty) {
      e['salaryMaxLpa'] = 'Enter the maximum salary';
    } else {
      maxS = parseLpa(maxSalary).value;
      if (maxS == null || maxS <= 0) e['salaryMaxLpa'] = 'Enter a valid salary';
    }
    if (minS != null && maxS != null && minS > maxS && !e.containsKey('salaryMinLpa')) {
      e['salaryMinLpa'] = 'Minimum salary cannot be more than maximum salary';
    }

    final o = int.tryParse(openings.trim());
    if (o == null || o < 1 || o > 1000) e['openings'] = 'Openings must be between 1 and 1000';
    if (description.length > 3000) e['description'] = 'Keep the description under 3000 characters';
    return e;
  }

  /// Body for POST /jobs and PUT /jobs/:id. Call only when [validate] is empty.
  Map<String, dynamic> toBody() => {
        'title': title.trim(),
        'skills': skills,
        'minExperienceYears': parseYears(minExp) ?? 0,
        'maxExperienceYears': maxExp.trim().isEmpty ? null : parseYears(maxExp),
        'salaryMinLpa': parseLpa(minSalary).value ?? 0,
        'salaryMaxLpa': parseLpa(maxSalary).value ?? 0,
        'location': location.trim(),
        'openings': int.tryParse(openings.trim()) ?? 1,
        'workMode': workMode,
        'employmentType': employmentType,
        'description': description.trim(),
      };
}
