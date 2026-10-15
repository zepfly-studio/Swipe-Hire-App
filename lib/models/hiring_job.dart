/// Funnel numbers shown on a job card (GET /jobs/mine `stats`).
class JobStats {
  final int swiped;
  final int shortlisted;
  final int interviewing;
  final int hired;

  const JobStats({this.swiped = 0, this.shortlisted = 0, this.interviewing = 0, this.hired = 0});

  factory JobStats.fromMap(Object? raw) {
    if (raw is! Map) return const JobStats();
    int n(String k) => (raw[k] as num?)?.toInt() ?? 0;
    return JobStats(
      swiped: n('swiped'),
      shortlisted: n('shortlisted'),
      interviewing: n('interviewing'),
      hired: n('hired'),
    );
  }
}

/// One of the company's jobs, as the new company side sees it
/// (`/jobs/mine`, `/jobs`, `/jobs/:id/status`). Salaries are LPA.
class HiringJob {
  final String id;
  final String title;
  final String description;
  final List<String> skills;
  final String location;

  /// full-time | part-time | internship | contract
  final String employmentType;

  /// onsite | hybrid | remote
  final String workMode;
  final int openings;
  final double salaryMinLpa;
  final double salaryMaxLpa;
  final double minExperienceYears;

  /// Null = no upper limit.
  final double? maxExperienceYears;

  /// open | paused | closed
  final String status;
  final DateTime? createdAt;
  final JobStats stats;

  const HiringJob({
    required this.id,
    required this.title,
    this.description = '',
    this.skills = const [],
    this.location = '',
    this.employmentType = 'full-time',
    this.workMode = 'onsite',
    this.openings = 1,
    this.salaryMinLpa = 0,
    this.salaryMaxLpa = 0,
    this.minExperienceYears = 0,
    this.maxExperienceYears,
    this.status = 'open',
    this.createdAt,
    this.stats = const JobStats(),
  });

  bool get isOpen => status == 'open';
  bool get isPaused => status == 'paused';
  bool get isClosed => status == 'closed';

  static String _num(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  /// "₹3–8 LPA" or "Up to ₹8 LPA"; empty when no salary is set.
  String get salaryLabel {
    if (salaryMaxLpa <= 0) return '';
    if (salaryMinLpa > 0 && salaryMinLpa < salaryMaxLpa) {
      return '₹${_num(salaryMinLpa)}–${_num(salaryMaxLpa)} LPA';
    }
    return 'Up to ₹${_num(salaryMaxLpa)} LPA';
  }

  /// "2–5 yrs" (the max can be ∞).
  String get experienceLabel {
    final min = _num(minExperienceYears);
    final max = maxExperienceYears == null ? '∞' : _num(maxExperienceYears!);
    return '$min–$max yrs';
  }

  String get workModeLabel => switch (workMode) {
        'hybrid' => 'Hybrid',
        'remote' => 'Remote',
        _ => 'On-site',
      };

  String get employmentTypeLabel => switch (employmentType) {
        'part-time' => 'part time',
        'internship' => 'internship',
        'contract' => 'contract',
        _ => 'full time',
      };

  static double _d(Object? v) => v is num ? v.toDouble() : (double.tryParse('$v') ?? 0);

  factory HiringJob.fromMap(Map<String, dynamic> m) {
    final rawStatus = (m['status'] ?? '').toString();
    var status = const {'open', 'paused', 'closed'}.contains(rawStatus) ? rawStatus : '';
    if (status.isEmpty) status = m['isOpen'] == false ? 'paused' : 'open';
    return HiringJob(
      id: (m['id'] ?? '').toString(),
      title: (m['title'] ?? '').toString(),
      description: (m['description'] ?? '').toString(),
      skills: m['skills'] is List ? (m['skills'] as List).map((e) => e.toString()).toList() : const [],
      location: (m['location'] ?? '').toString(),
      employmentType: (m['employmentType'] ?? 'full-time').toString(),
      workMode: (m['workMode'] ?? 'onsite').toString(),
      openings: (m['openings'] as num?)?.toInt() ?? 1,
      salaryMinLpa: _d(m['salaryMinLpa']),
      salaryMaxLpa: _d(m['salaryMaxLpa']),
      minExperienceYears: _d(m['minExperienceYears']),
      maxExperienceYears: m['maxExperienceYears'] is num ? (m['maxExperienceYears'] as num).toDouble() : null,
      status: status,
      createdAt: DateTime.tryParse((m['createdAt'] ?? '').toString()),
      stats: JobStats.fromMap(m['stats']),
    );
  }

  /// The editable fields, as POST /jobs and PUT /jobs/:id take them.
  Map<String, dynamic> toBody() => {
        'title': title,
        'description': description,
        'skills': skills,
        'location': location,
        'employmentType': employmentType,
        'workMode': workMode,
        'openings': openings,
        'salaryMinLpa': salaryMinLpa,
        'salaryMaxLpa': salaryMaxLpa,
        'minExperienceYears': minExperienceYears,
        'maxExperienceYears': maxExperienceYears,
      };
}
