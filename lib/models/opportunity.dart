/// Where a candidate stands with one recruiter/company -- the thing a
/// candidate's "Hiring Activity" section and a recruiter's "Pipeline" tab
/// both read and write.
///
/// [taskAssigned] and [taskSubmitted] are driven by the task flow and
/// [withdrawn] by the candidate (withdrawing, or declining an offer); a
/// recruiter never picks those by hand.
enum OpportunityStatus {
  applied,
  shortlisted,
  taskAssigned,
  taskSubmitted,
  interviewScheduled,
  offered,
  rejected,
  hired,
  withdrawn,
}

/// Where one assessment task stands. `assigned` also covers "the recruiter
/// asked for changes" (then [OpportunityTask.feedback] is filled in).
enum TaskStatus { assigned, submitted, approved, rejected }

extension TaskStatusX on TaskStatus {
  static TaskStatus fromString(String value) {
    return TaskStatus.values.firstWhere((e) => e.name == value, orElse: () => TaskStatus.assigned);
  }
}

DateTime? _parseDate(dynamic value) => DateTime.tryParse(value?.toString() ?? '')?.toLocal();

/// A small assessment a recruiter assigns to a shortlisted candidate. The
/// candidate submits an answer, a link and/or a file, the recruiter reviews
/// it, and an approved task is what leads into scheduling the interview.
class OpportunityTask {
  final String id;
  final String opportunityId;
  final String title;
  final String description;
  final String link;
  final DateTime? dueDate;
  final TaskStatus status;
  final String answer;
  final String submissionLink;
  final String submissionFileUrl;
  final String submissionFileName;
  final DateTime? submittedAt;
  final String feedback;
  final DateTime? reviewedAt;

  const OpportunityTask({
    required this.id,
    required this.opportunityId,
    required this.title,
    this.description = '',
    this.link = '',
    this.dueDate,
    this.status = TaskStatus.assigned,
    this.answer = '',
    this.submissionLink = '',
    this.submissionFileUrl = '',
    this.submissionFileName = '',
    this.submittedAt,
    this.feedback = '',
    this.reviewedAt,
  });

  factory OpportunityTask.fromMap(Map<String, dynamic> map) {
    return OpportunityTask(
      id: map['id'] ?? '',
      opportunityId: map['opportunityId'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      link: map['link'] ?? '',
      dueDate: _parseDate(map['dueDate']),
      status: TaskStatusX.fromString(map['status'] ?? 'assigned'),
      answer: map['answer'] ?? '',
      submissionLink: map['submissionLink'] ?? '',
      submissionFileUrl: map['submissionFileUrl'] ?? '',
      submissionFileName: map['submissionFileName'] ?? '',
      submittedAt: _parseDate(map['submittedAt']),
      feedback: map['feedback'] ?? '',
      reviewedAt: _parseDate(map['reviewedAt']),
    );
  }

  /// Still waiting on the candidate and past its due date.
  bool get isOverdue => status == TaskStatus.assigned && dueDate != null && DateTime.now().isAfter(dueDate!);

  /// Handed in after the due date.
  bool get wasSubmittedLate => submittedAt != null && dueDate != null && submittedAt!.isAfter(dueDate!);

  /// The recruiter sent it back with a note.
  bool get hasChangeRequest => status == TaskStatus.assigned && feedback.isNotEmpty;

  /// Something is attached to the submission (answer, link or file).
  bool get hasSubmission => answer.isNotEmpty || submissionLink.isNotEmpty || submissionFileUrl.isNotEmpty;
}

extension OpportunityStatusX on OpportunityStatus {
  static OpportunityStatus fromString(String value) {
    return OpportunityStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => OpportunityStatus.shortlisted,
    );
  }

  String get label => switch (this) {
        OpportunityStatus.applied => 'Applied',
        OpportunityStatus.shortlisted => 'Shortlisted',
        OpportunityStatus.taskAssigned => 'Task assigned',
        OpportunityStatus.taskSubmitted => 'Task submitted',
        OpportunityStatus.interviewScheduled => 'Interview scheduled',
        OpportunityStatus.offered => 'Offer extended',
        OpportunityStatus.rejected => 'Not selected',
        OpportunityStatus.hired => 'Hired',
        OpportunityStatus.withdrawn => 'Withdrawn',
      };

  /// Statuses a recruiter can pick by hand in the editor and the quick-move
  /// menu. The rest are set by the task flow and by the candidate.
  bool get isManual =>
      this != OpportunityStatus.applied &&
      this != OpportunityStatus.taskAssigned &&
      this != OpportunityStatus.taskSubmitted &&
      this != OpportunityStatus.withdrawn;

  /// Nothing more to do on this entry from either side.
  bool get isClosed =>
      this == OpportunityStatus.hired || this == OpportunityStatus.rejected || this == OpportunityStatus.withdrawn;
}

/// How the candidate answered the interview invite.
enum InterviewResponse { none, confirmed, rescheduleRequested }

InterviewResponse _interviewResponseOf(String? value) => switch (value) {
      'confirmed' => InterviewResponse.confirmed,
      'reschedule_requested' => InterviewResponse.rescheduleRequested,
      _ => InterviewResponse.none,
    };

/// One recruiter's hiring interaction with one candidate (backend:
/// `opportunities` table): status, an optional interview schedule, and an
/// optional offer. A candidate only ever reads their own; a recruiter only
/// ever reads/writes the ones they created (enforced by the backend).
class Opportunity {
  final String id;
  final String candidateUid;
  final String candidateName;
  final String recruiterUid;
  final String companyName;
  final bool companyVerified;
  final String recruiterName;
  final String role;

  /// Set when this opportunity started from a candidate applying to a
  /// [JobPosting] (JobPostingService.apply) rather than a recruiter
  /// reaching out first -- empty for the latter.
  final String jobPostingId;
  final OpportunityStatus status;
  final DateTime? interviewDate;
  final String interviewMode;
  final String interviewDetails;
  final InterviewResponse interviewResponse;
  final String interviewResponseNote;
  final double? offerSalaryLpa;
  final DateTime? offerJoiningDate;
  final String offerNotes;

  /// `accepted`, `declined`, or empty while the offer is unanswered.
  final String offerResponse;
  final DateTime? updatedAt;

  /// The task that needs attention first (one waiting on the candidate,
  /// then one waiting on the recruiter, then the newest) -- what a tile
  /// shows. [tasks] has all of them, newest first.
  final OpportunityTask? task;
  final List<OpportunityTask> tasks;

  /// Chat messages from the other side that the viewer hasn't opened.
  final int unreadCount;

  const Opportunity({
    this.id = '',
    required this.candidateUid,
    required this.candidateName,
    required this.recruiterUid,
    required this.companyName,
    this.companyVerified = false,
    required this.recruiterName,
    required this.role,
    this.jobPostingId = '',
    this.status = OpportunityStatus.shortlisted,
    this.interviewDate,
    this.interviewMode = '',
    this.interviewDetails = '',
    this.interviewResponse = InterviewResponse.none,
    this.interviewResponseNote = '',
    this.offerSalaryLpa,
    this.offerJoiningDate,
    this.offerNotes = '',
    this.offerResponse = '',
    this.updatedAt,
    this.task,
    this.tasks = const [],
    this.unreadCount = 0,
  });

  factory Opportunity.fromMap(String id, Map<String, dynamic> map) {
    final taskList = (map['tasks'] as List? ?? const [])
        .map((e) => OpportunityTask.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    final primary = map['task'] is Map ? OpportunityTask.fromMap(Map<String, dynamic>.from(map['task'] as Map)) : null;
    return Opportunity(
      id: id,
      candidateUid: map['candidateUid'] ?? '',
      candidateName: map['candidateName'] ?? '',
      recruiterUid: map['recruiterUid'] ?? '',
      companyName: map['companyName'] ?? '',
      companyVerified: map['companyVerified'] == true,
      recruiterName: map['recruiterName'] ?? '',
      role: map['role'] ?? '',
      jobPostingId: map['jobPostingId'] ?? '',
      status: OpportunityStatusX.fromString(map['status'] ?? 'shortlisted'),
      interviewDate: _parseDate(map['interviewDate']),
      interviewMode: map['interviewMode'] ?? '',
      interviewDetails: map['interviewDetails'] ?? '',
      interviewResponse: _interviewResponseOf(map['interviewResponse'] as String?),
      interviewResponseNote: map['interviewResponseNote'] ?? '',
      offerSalaryLpa: (map['offerSalaryLpa'] as num?)?.toDouble(),
      offerJoiningDate: _parseDate(map['offerJoiningDate']),
      offerNotes: map['offerNotes'] ?? '',
      offerResponse: map['offerResponse'] ?? '',
      updatedAt: _parseDate(map['updatedAt']),
      task: primary,
      tasks: taskList.isNotEmpty ? taskList : (primary == null ? const [] : [primary]),
      unreadCount: (map['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// Tasks still waiting on the candidate.
  List<OpportunityTask> get pendingTasks => tasks.where((t) => t.status == TaskStatus.assigned).toList();

  /// Tasks the recruiter still has to review.
  List<OpportunityTask> get tasksToReview => tasks.where((t) => t.status == TaskStatus.submitted).toList();

  /// Moves this opportunity to [newStatus], same as editing it through
  /// [HiringPipelineScreen]'s full editor -- interview/offer fields are
  /// kept only if the new status still uses them (e.g. moving back from
  /// "Interview scheduled" to "Shortlisted" clears the interview slot
  /// rather than leaving stale data behind).
  Opportunity copyWithStatus(OpportunityStatus newStatus) {
    final keepsInterview = newStatus == OpportunityStatus.interviewScheduled;
    final keepsOffer = newStatus == OpportunityStatus.offered || newStatus == OpportunityStatus.hired;
    return Opportunity(
      id: id,
      candidateUid: candidateUid,
      candidateName: candidateName,
      recruiterUid: recruiterUid,
      companyName: companyName,
      companyVerified: companyVerified,
      recruiterName: recruiterName,
      role: role,
      jobPostingId: jobPostingId,
      status: newStatus,
      interviewDate: keepsInterview ? interviewDate : null,
      interviewMode: keepsInterview ? interviewMode : '',
      interviewDetails: keepsInterview ? interviewDetails : '',
      interviewResponse: keepsInterview ? interviewResponse : InterviewResponse.none,
      interviewResponseNote: keepsInterview ? interviewResponseNote : '',
      offerSalaryLpa: keepsOffer ? offerSalaryLpa : null,
      offerJoiningDate: keepsOffer ? offerJoiningDate : null,
      offerNotes: keepsOffer ? offerNotes : '',
      offerResponse: keepsOffer ? offerResponse : '',
      task: task,
      tasks: tasks,
      unreadCount: unreadCount,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'candidateUid': candidateUid,
      'candidateName': candidateName,
      'recruiterUid': recruiterUid,
      'companyName': companyName,
      'recruiterName': recruiterName,
      'role': role,
      'jobPostingId': jobPostingId,
      'status': status.name,
      'interviewDate': interviewDate?.toUtc().toIso8601String(),
      'interviewMode': interviewMode,
      'interviewDetails': interviewDetails,
      'offerSalaryLpa': offerSalaryLpa,
      'offerJoiningDate': offerJoiningDate?.toUtc().toIso8601String(),
      'offerNotes': offerNotes,
      'updatedAt': updatedAt?.toUtc().toIso8601String(),
    };
  }
}
