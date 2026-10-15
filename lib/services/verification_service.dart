import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';

// -- Input rules ------------------------------------------------------------

/// The server's GSTIN format (`backend` `^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$`).
final RegExp _gstinRe = RegExp(r'^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');

/// Upper-cases a GSTIN and removes every whitespace character.
String normalizeGstin(String raw) => raw.replaceAll(RegExp(r'\s+'), '').toUpperCase();

/// A GSTIN as typed is 15 characters long once normalised; the Submit button
/// opens at that point (the server then checks the format).
bool gstinHasFullLength(String raw) => normalizeGstin(raw).length == 15;

/// Whether the normalised [raw] matches the government GSTIN format.
bool isValidGstin(String raw) => _gstinRe.hasMatch(normalizeGstin(raw));

/// The text shown for a GSTIN that is 15 characters but not well formed
/// (same words as the server's field error).
const String kInvalidGstinMessage = 'Please enter a valid 15-character GSTIN';

/// Digits only (what the 6-digit email code field keeps).
String digitsOnly(String raw) => raw.replaceAll(RegExp(r'\D'), '');

/// The email code is exactly six digits; Verify stays disabled until then.
bool isCompleteEmailCode(String raw) => RegExp(r'^\d{6}$').hasMatch(raw);

/// Keeps a GSTIN field upper-case with no spaces. Pair with a
/// [LengthLimitingTextInputFormatter] of 15 *after* it.
class GstinInputFormatter extends TextInputFormatter {
  const GstinInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = normalizeGstin(newValue.text);
    if (text == newValue.text) return newValue;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

// -- Models -----------------------------------------------------------------

/// `GET /company/verification`: where the company stands.
class VerificationInfo {
  const VerificationInfo({
    this.status = 'none',
    this.method = '',
    this.verifiedAt,
    this.gstin = '',
    this.website = '',
    this.email = '',
  });

  /// none | pending | verified | rejected
  final String status;

  /// `email` | `gst` | ''
  final String method;
  final DateTime? verifiedAt;
  final String gstin;
  final String website;

  /// The caller's login email.
  final String email;

  bool get isVerified => status == 'verified';
  bool get isPending => status == 'pending';
  bool get isRejected => status == 'rejected';

  static String _s(Object? v) => (v ?? '').toString();

  /// Maps the server's `unverified` onto `none`.
  static String normalizeStatus(Object? raw) {
    final s = _s(raw);
    return switch (s) {
      '' || 'unverified' => 'none',
      _ => s,
    };
  }

  factory VerificationInfo.fromResponse(Map<String, dynamic> res) {
    final v = res['verification'] is Map ? Map<String, dynamic>.from(res['verification'] as Map) : const <String, dynamic>{};
    return VerificationInfo(
      status: normalizeStatus(v['status']),
      method: _s(v['method']),
      verifiedAt: DateTime.tryParse(_s(v['verifiedAt']))?.toLocal(),
      gstin: _s(res['gstin']),
      website: _s(res['website']),
      email: _s(res['email']),
    );
  }

  /// A copy with the answer of a send/confirm/submit call applied.
  VerificationInfo withVerificationFrom(Map<String, dynamic> res, {String? gstin}) {
    final v = res['verification'] is Map ? Map<String, dynamic>.from(res['verification'] as Map) : const <String, dynamic>{};
    return VerificationInfo(
      status: v['status'] == null ? status : normalizeStatus(v['status']),
      method: v['method'] == null ? method : _s(v['method']),
      verifiedAt: DateTime.tryParse(_s(v['verifiedAt']))?.toLocal() ?? verifiedAt,
      gstin: gstin ?? this.gstin,
      website: website,
      email: email,
    );
  }
}

/// `POST /company/verification/email/send` answer.
class EmailCodeSent {
  const EmailCodeSent({required this.sentTo, this.devCode = ''});

  /// The address the code went to.
  final String sentTo;

  /// Only present when the server has no working mail sender (testing).
  final String devCode;
}

// -- Service ----------------------------------------------------------------

/// Company verification (docs/PHASE4_CONTRACT.md): work-email code and GSTIN.
/// Errors are [ApiException]s whose `message` is shown as-is.
class VerificationService {
  VerificationService._internal({ApiClient? api}) : _api = api ?? ApiClient.instance;
  static final VerificationService instance = VerificationService._internal();

  @visibleForTesting
  factory VerificationService.test(ApiClient api) => VerificationService._internal(api: api);

  final ApiClient _api;

  Future<VerificationInfo> fetch() async => VerificationInfo.fromResponse(await _api.get('/company/verification'));

  /// Emails a 6-digit code to the caller's login address.
  Future<EmailCodeSent> sendEmailCode() async {
    final res = await _api.post('/company/verification/email/send');
    return EmailCodeSent(
      sentTo: (res['sentTo'] ?? '').toString(),
      devCode: (res['devCode'] ?? '').toString(),
    );
  }

  /// Confirms the code; the company is verified on success.
  Future<VerificationInfo> confirmEmailCode(String code, {VerificationInfo? current}) async {
    final res = await _api.post('/company/verification/email/confirm', body: {'code': code.trim()});
    return (current ?? const VerificationInfo()).withVerificationFrom(res);
  }

  /// Asks the team to review a GSTIN. The status becomes `pending`.
  Future<VerificationInfo> submitGstin(String gstin, {VerificationInfo? current}) async {
    final normalized = normalizeGstin(gstin);
    final res = await _api.post('/company/verification/gst', body: {'gstin': normalized});
    return (current ?? const VerificationInfo()).withVerificationFrom(res, gstin: normalized);
  }
}
