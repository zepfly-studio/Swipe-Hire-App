int _n(dynamic v) =>
    v is num ? v.round() : (v is String ? int.tryParse(v) ?? 0 : 0);
String _s(dynamic v) => v == null ? '' : v.toString();

/// One company that shortlisted the candidate and has made contact
/// (`GET /candidates/me/stats` -> `shortlistedBy[]`).
class ShortlistedBy {
  final String id;
  final String recruiterId;
  final String companyId;
  final String companyName;
  final String industry;
  final String hiringFor;
  final String location;
  final bool verified;
  final String logoUrl;

  /// The raw OpportunityStatus string: shortlisted, taskAssigned,
  /// taskSubmitted, interviewScheduled, offered, hired, rejected, withdrawn...
  final String stage;
  final DateTime? date;

  const ShortlistedBy({
    this.id = '',
    this.recruiterId = '',
    this.companyId = '',
    this.companyName = '',
    this.industry = '',
    this.hiringFor = '',
    this.location = '',
    this.verified = false,
    this.logoUrl = '',
    this.stage = '',
    this.date,
  });

  factory ShortlistedBy.fromMap(Map<String, dynamic> m) {
    final d = m['date'];
    return ShortlistedBy(
      id: _s(m['id']),
      recruiterId: _s(m['recruiterId']),
      companyId: _s(m['companyId']),
      companyName: _s(m['companyName']),
      industry: _s(m['industry']),
      hiringFor: _s(m['hiringFor']),
      location: _s(m['location']),
      verified: m['verified'] == true,
      logoUrl: _s(m['logoUrl']),
      stage: _s(m['stage']),
      date: d is String ? DateTime.tryParse(d)?.toLocal() : null,
    );
  }

  /// "Shortlisted", "Task sent", "Selected" ... shown on the row's pill.
  String get stageLabel => switch (stage) {
    'contacted' || 'applied' => 'Contacted',
    'task' || 'taskAssigned' || 'taskSubmitted' => 'Task sent',
    'interview' || 'interviewScheduled' => 'Interview',
    'offered' => 'Offer',
    'hired' => 'Selected',
    'rejected' || 'closed' || 'withdrawn' => 'Closed',
    _ => 'Shortlisted',
  };

  /// `id` is the opportunity id, which the existing chat needs.
  String get opportunityId => id;

  /// "{job} · {location}", skipping whichever is empty.
  String get subtitle =>
      [hiringFor, location].where((e) => e.isNotEmpty).join(' · ');
}

/// `GET /candidates/me/stats`.
class CandidateStats {
  final int viewedCount;
  final int wishlistedCount;
  final int shortlistedCount;
  final int hiddenCount;
  final List<ShortlistedBy> shortlistedBy;

  const CandidateStats({
    this.viewedCount = 0,
    this.wishlistedCount = 0,
    this.shortlistedCount = 0,
    this.hiddenCount = 0,
    this.shortlistedBy = const [],
  });

  factory CandidateStats.fromMap(Map<String, dynamic> m) {
    final by = [
      for (final e
          in (m['shortlistedBy'] is List
              ? m['shortlistedBy'] as List
              : const []))
        if (e is Map) ShortlistedBy.fromMap(Map<String, dynamic>.from(e)),
    ];
    final hidden = _n(m['hiddenCount']);
    return CandidateStats(
      viewedCount: _n(m['viewedCount']),
      wishlistedCount: _n(m['wishlistedCount']),
      // The server count when present, else the website's definition:
      // contacted companies + the ones that have not made contact yet.
      shortlistedCount: m['shortlistedCount'] != null
          ? _n(m['shortlistedCount'])
          : by.length + hidden,
      hiddenCount: hidden,
      shortlistedBy: by,
    );
  }
}
