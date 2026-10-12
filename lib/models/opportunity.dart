import 'package:cloud_firestore/cloud_firestore.dart';

/// Where a candidate stands with one recruiter/company -- the thing a
/// candidate's "Hiring Activity" section and a recruiter's "Pipeline" tab
/// both read and write.
enum OpportunityStatus { shortlisted, interviewScheduled, offered, rejected, hired }

extension OpportunityStatusX on OpportunityStatus {
  static OpportunityStatus fromString(String value) {
    return OpportunityStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => OpportunityStatus.shortlisted,
    );
  }

  String get label => switch (this) {
        OpportunityStatus.shortlisted => 'Shortlisted',
        OpportunityStatus.interviewScheduled => 'Interview scheduled',
        OpportunityStatus.offered => 'Offer extended',
        OpportunityStatus.rejected => 'Not selected',
        OpportunityStatus.hired => 'Hired',
      };
}

/// `opportunities/{id}` -- one recruiter's hiring interaction with one
/// candidate: status, an optional interview schedule, and an optional
/// offer. A candidate only ever reads their own; a recruiter only ever
/// reads/writes the ones they created (enforced in firestore.rules).
class Opportunity {
  final String id;
  final String candidateUid;
  final String candidateName;
  final String recruiterUid;
  final String companyName;
  final String recruiterName;
  final String role;
  final OpportunityStatus status;
  final DateTime? interviewDate;
  final String interviewMode;
  final String interviewDetails;
  final double? offerSalaryLpa;
  final DateTime? offerJoiningDate;
  final String offerNotes;
  final DateTime? updatedAt;

  const Opportunity({
    this.id = '',
    required this.candidateUid,
    required this.candidateName,
    required this.recruiterUid,
    required this.companyName,
    required this.recruiterName,
    required this.role,
    this.status = OpportunityStatus.shortlisted,
    this.interviewDate,
    this.interviewMode = '',
    this.interviewDetails = '',
    this.offerSalaryLpa,
    this.offerJoiningDate,
    this.offerNotes = '',
    this.updatedAt,
  });

  factory Opportunity.fromMap(String id, Map<String, dynamic> map) {
    return Opportunity(
      id: id,
      candidateUid: map['candidateUid'] ?? '',
      candidateName: map['candidateName'] ?? '',
      recruiterUid: map['recruiterUid'] ?? '',
      companyName: map['companyName'] ?? '',
      recruiterName: map['recruiterName'] ?? '',
      role: map['role'] ?? '',
      status: OpportunityStatusX.fromString(map['status'] ?? 'shortlisted'),
      interviewDate: (map['interviewDate'] as Timestamp?)?.toDate(),
      interviewMode: map['interviewMode'] ?? '',
      interviewDetails: map['interviewDetails'] ?? '',
      offerSalaryLpa: (map['offerSalaryLpa'] as num?)?.toDouble(),
      offerJoiningDate: (map['offerJoiningDate'] as Timestamp?)?.toDate(),
      offerNotes: map['offerNotes'] ?? '',
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
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
      'status': status.name,
      'interviewDate': interviewDate == null ? null : Timestamp.fromDate(interviewDate!),
      'interviewMode': interviewMode,
      'interviewDetails': interviewDetails,
      'offerSalaryLpa': offerSalaryLpa,
      'offerJoiningDate': offerJoiningDate == null ? null : Timestamp.fromDate(offerJoiningDate!),
      'offerNotes': offerNotes,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
