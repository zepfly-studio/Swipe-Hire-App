import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// One pending GSTIN verification (`GET /admin/verifications`).
class AdminVerificationRequest {
  const AdminVerificationRequest({
    required this.id,
    required this.companyName,
    this.website = '',
    this.location = '',
    this.gstin = '',
    this.contactName = '',
    this.contactEmail = '',
    this.requestedAt,
  });

  /// The company's owner user id.
  final String id;
  final String companyName;
  final String website;
  final String location;
  final String gstin;
  final String contactName;
  final String contactEmail;
  final DateTime? requestedAt;

  /// "contact name · contact email · location · website", skipping blanks.
  String get detailLine => [contactName, contactEmail, location, website].where((s) => s.trim().isNotEmpty).join(' · ');

  static String _s(Object? v) => (v ?? '').toString();

  static AdminVerificationRequest? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final id = _s(m['id']);
    if (id.isEmpty) return null;
    final contact = m['contact'] is Map ? Map<String, dynamic>.from(m['contact'] as Map) : const <String, dynamic>{};
    return AdminVerificationRequest(
      id: id,
      companyName: _s(m['companyName']).isEmpty ? 'Company' : _s(m['companyName']),
      website: _s(m['website']),
      location: _s(m['location']),
      gstin: _s(m['gstin']),
      contactName: _s(contact['name']),
      contactEmail: _s(contact['email']),
      requestedAt: DateTime.tryParse(_s(m['requestedAt']))?.toLocal(),
    );
  }
}

/// `/admin/*` -- review of GSTIN verification requests (admins only; others
/// get 403 "Admins only").
class AdminService {
  AdminService._internal({ApiClient? api}) : _api = api ?? ApiClient.instance;
  static final AdminService instance = AdminService._internal();

  @visibleForTesting
  factory AdminService.test(ApiClient api) => AdminService._internal(api: api);

  final ApiClient _api;

  /// Pending requests, oldest first.
  Future<List<AdminVerificationRequest>> pendingVerifications() async {
    final res = await _api.get('/admin/verifications');
    return [
      for (final e in (res['companies'] as List? ?? const []))
        ?AdminVerificationRequest.tryParse(e),
    ];
  }

  /// Approves (verified by GSTIN) or rejects a request. 404 means there is no
  /// pending request for that company (already decided).
  Future<void> decide(String companyId, {required bool approve}) async {
    await _api.post('/admin/verifications/${Uri.encodeComponent(companyId)}', body: {'approve': approve});
  }
}
