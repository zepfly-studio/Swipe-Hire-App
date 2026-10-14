import 'package:flutter/foundation.dart';
import '../models/company.dart';
import '../models/job_posting.dart';
import 'api_client.dart';
import 'polling.dart';

/// A company page together with its open postings.
class CompanyPage {
  final CompanyProfile company;
  final List<JobPosting> jobs;
  const CompanyPage({required this.company, required this.jobs});
}

/// The recruiter's company profile and the public company page candidates
/// see (`/company` routes).
class CompanyService {
  CompanyService._internal({ApiClient? api}) : _api = api ?? ApiClient.instance;
  static final CompanyService instance = CompanyService._internal();

  @visibleForTesting
  factory CompanyService.test(ApiClient api) => CompanyService._internal(api: api);

  final ApiClient _api;

  /// The signed-in recruiter's company, or null if they haven't made one.
  Future<CompanyProfile?> fetchMine() async {
    final res = await _api.get('/company/me');
    final company = res['company'];
    return company is Map ? CompanyProfile.fromMap(Map<String, dynamic>.from(company)) : null;
  }

  /// A name to pre-fill the form with (the one given at signup).
  Future<String> suggestedName() async {
    final res = await _api.get('/company/me');
    return (res['suggestedName'] as String?) ?? '';
  }

  /// Saves the company. A website on the same domain as the recruiter's
  /// work email verifies it automatically.
  Future<CompanyProfile> save(CompanyProfile company) async {
    final res = await _api.put('/company/me', body: company.toMap());
    DataRefresh.instance.bump();
    return CompanyProfile.fromMap(Map<String, dynamic>.from(res['company'] as Map));
  }

  Future<CompanyProfile> requestVerification({String note = ''}) async {
    final res = await _api.post('/company/me/verification-request', body: {'note': note});
    DataRefresh.instance.bump();
    return CompanyProfile.fromMap(Map<String, dynamic>.from(res['company'] as Map));
  }

  Future<CompanyPage?> fetchPublic(String companyId) async {
    try {
      final res = await _api.get('/company/$companyId');
      final jobs = (res['jobs'] as List? ?? const [])
          .map((e) => JobPosting.fromMap(e['id'] as String, Map<String, dynamic>.from(e as Map)))
          .toList();
      return CompanyPage(
        company: CompanyProfile.fromMap(Map<String, dynamic>.from(res['company'] as Map)),
        jobs: jobs,
      );
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }
}
