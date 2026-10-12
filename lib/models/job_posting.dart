import 'package:cloud_firestore/cloud_firestore.dart';

/// `job_postings/{id}` -- a role a recruiter is hiring for, browsable by
/// every candidate account. Candidates apply to it (JobPostingService.apply),
/// which creates an [Opportunity] the recruiter then manages on their
/// Pipeline tab exactly like a recruiter-initiated contact.
class JobPosting {
  final String id;
  final String recruiterUid;
  final String recruiterName;
  final String companyName;
  final String title;
  final String description;
  final List<String> skills;
  final String location;
  final String employmentType;
  final double salaryMinLpa;
  final double salaryMaxLpa;
  final bool isOpen;
  final DateTime? createdAt;

  const JobPosting({
    this.id = '',
    required this.recruiterUid,
    required this.recruiterName,
    required this.companyName,
    required this.title,
    required this.description,
    required this.skills,
    required this.location,
    required this.employmentType,
    this.salaryMinLpa = 0,
    this.salaryMaxLpa = 0,
    this.isOpen = true,
    this.createdAt,
  });

  factory JobPosting.fromMap(String id, Map<String, dynamic> map) {
    return JobPosting(
      id: id,
      recruiterUid: map['recruiterUid'] ?? '',
      recruiterName: map['recruiterName'] ?? '',
      companyName: map['companyName'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      skills: List<String>.from(map['skills'] ?? const []),
      location: map['location'] ?? '',
      employmentType: map['employmentType'] ?? '',
      salaryMinLpa: (map['salaryMinLpa'] ?? 0).toDouble(),
      salaryMaxLpa: (map['salaryMaxLpa'] ?? 0).toDouble(),
      isOpen: map['isOpen'] ?? true,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'recruiterUid': recruiterUid,
      'recruiterName': recruiterName,
      'companyName': companyName,
      'title': title,
      'description': description,
      'skills': skills,
      'location': location,
      'employmentType': employmentType,
      'salaryMinLpa': salaryMinLpa,
      'salaryMaxLpa': salaryMaxLpa,
      'isOpen': isOpen,
      'createdAt': createdAt == null ? FieldValue.serverTimestamp() : Timestamp.fromDate(createdAt!),
    };
  }
}
