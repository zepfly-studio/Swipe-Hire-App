import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/services/admin_service.dart';
import 'package:hiring_app/services/api_client.dart';
import 'package:hiring_app/services/verification_service.dart';

/// Records calls and answers from a "METHOD path" -> body map; an entry in
/// [errors] is thrown instead.
class StubApi extends ApiClient {
  StubApi(this.responses, {this.errors = const {}}) : super.forTest();
  final Map<String, Map<String, dynamic>> responses;
  final Map<String, ApiException> errors;
  final List<String> calls = [];
  final List<Map<String, dynamic>?> bodies = [];

  Map<String, dynamic> _answer(String method, String path, Map<String, dynamic>? body) {
    final key = '$method $path';
    calls.add(key);
    bodies.add(body);
    final error = errors[key];
    if (error != null) throw error;
    return responses[key] ?? const {};
  }

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) async => _answer('GET', path, null);

  @override
  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body}) async => _answer('POST', path, body);
}

void main() {
  group('GSTIN input rules', () {
    test('normalizeGstin upper-cases and strips all whitespace', () {
      expect(normalizeGstin(' 22aaaaa 0000a\t1z5\n'), '22AAAAA0000A1Z5');
    });

    test('full length is 15 characters after normalising', () {
      expect(gstinHasFullLength('22AAAAA0000A1Z'), isFalse);
      expect(gstinHasFullLength('22aaaaa0000a1z5'), isTrue);
      expect(gstinHasFullLength('22 AAAAA 0000 A1Z5'), isTrue);
      expect(gstinHasFullLength('22AAAAA0000A1Z55'), isFalse);
    });

    test('isValidGstin follows the server regex', () {
      expect(isValidGstin('22AAAAA0000A1Z5'), isTrue);
      expect(isValidGstin('27aapfu0939f1zv'), isTrue);
      expect(isValidGstin('22AAAAA0000A0Z5'), isFalse); // entity digit can't be 0
      expect(isValidGstin('22AAAAA0000A1X5'), isFalse); // 14th char must be Z
      expect(isValidGstin('AAAAAAA0000A1Z5'), isFalse); // state code is digits
      expect(isValidGstin(''), isFalse);
    });

    test('the input formatter upper-cases and removes spaces as you type', () {
      const formatter = GstinInputFormatter();
      final out = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '22aa aaa', selection: TextSelection.collapsed(offset: 8)),
      );
      expect(out.text, '22AAAAA');
      expect(out.selection.baseOffset, 7);
    });
  });

  group('email code rules', () {
    test('only exactly six digits enable Verify', () {
      expect(isCompleteEmailCode(''), isFalse);
      expect(isCompleteEmailCode('12345'), isFalse);
      expect(isCompleteEmailCode('1234567'), isFalse);
      expect(isCompleteEmailCode('12a456'), isFalse);
      expect(isCompleteEmailCode('123456'), isTrue);
    });

    test('digitsOnly drops everything else', () {
      expect(digitsOnly('12 3-4a56'), '123456');
    });
  });

  group('VerificationService', () {
    test('fetch parses the status, method and extras', () async {
      final api = StubApi({
        'GET /company/verification': {
          'verification': {'status': 'pending', 'method': 'gst', 'verifiedAt': null},
          'gstin': '22AAAAA0000A1Z5',
          'website': 'acme.com',
          'email': 'hr@acme.com',
        },
      });
      final info = await VerificationService.test(api).fetch();
      expect(api.calls.single, 'GET /company/verification');
      expect(info.isPending, isTrue);
      expect(info.method, 'gst');
      expect(info.gstin, '22AAAAA0000A1Z5');
      expect(info.website, 'acme.com');
      expect(info.email, 'hr@acme.com');
    });

    test('unverified is shown as none', () {
      expect(VerificationInfo.normalizeStatus('unverified'), 'none');
      expect(VerificationInfo.fromResponse(const {}).status, 'none');
    });

    test('send hits the send endpoint and returns devCode when present', () async {
      final api = StubApi({
        'POST /company/verification/email/send': {'sentTo': 'hr@acme.com', 'devCode': '123456'},
      });
      final sent = await VerificationService.test(api).sendEmailCode();
      expect(api.calls.single, 'POST /company/verification/email/send');
      expect(sent.sentTo, 'hr@acme.com');
      expect(sent.devCode, '123456');

      final quiet = await VerificationService.test(StubApi({
        'POST /company/verification/email/send': {'sentTo': 'hr@acme.com'},
      })).sendEmailCode();
      expect(quiet.devCode, isEmpty);
    });

    test('confirm sends the code and returns the verified state', () async {
      final api = StubApi({
        'POST /company/verification/email/confirm': {
          'verification': {'status': 'verified', 'method': 'email', 'verifiedAt': '2026-10-15T10:00:00Z'},
        },
      });
      final info = await VerificationService.test(api).confirmEmailCode(' 123456 ');
      expect(api.bodies.single, {'code': '123456'});
      expect(info.isVerified, isTrue);
      expect(info.method, 'email');
      expect(info.verifiedAt, isNotNull);
    });

    test('a wrong code surfaces the server message', () async {
      final api = StubApi(const {}, errors: {
        'POST /company/verification/email/confirm': ApiException(400, 'Wrong code, please check and try again'),
      });
      await expectLater(
        VerificationService.test(api).confirmEmailCode('000000'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Wrong code, please check and try again')),
      );
    });

    test('submitGstin normalises, posts and keeps the GSTIN with pending status', () async {
      final api = StubApi({
        'POST /company/verification/gst': {
          'verification': {'status': 'pending', 'method': 'gst'},
        },
      });
      final info = await VerificationService.test(api).submitGstin(' 22aaaaa0000a1z5 ');
      expect(api.calls.single, 'POST /company/verification/gst');
      expect(api.bodies.single, {'gstin': '22AAAAA0000A1Z5'});
      expect(info.isPending, isTrue);
      expect(info.gstin, '22AAAAA0000A1Z5');
    });
  });

  group('AdminService', () {
    test('pending list parses rows and skips ones without an id', () async {
      final api = StubApi({
        'GET /admin/verifications': {
          'companies': [
            {
              'id': 'u1',
              'companyName': 'Acme',
              'website': 'acme.com',
              'location': 'Jaipur',
              'gstin': '22AAAAA0000A1Z5',
              'contact': {'name': 'Asha', 'email': 'asha@acme.com'},
              'requestedAt': '2026-10-14T08:00:00Z',
            },
            {'companyName': 'No id'},
          ],
        },
      });
      final rows = await AdminService.test(api).pendingVerifications();
      expect(rows, hasLength(1));
      expect(rows.single.id, 'u1');
      expect(rows.single.companyName, 'Acme');
      expect(rows.single.detailLine, 'Asha · asha@acme.com · Jaipur · acme.com');
      expect(rows.single.gstin, '22AAAAA0000A1Z5');
      expect(rows.single.requestedAt, isNotNull);
    });

    test('decide posts approve true / false to the company id', () async {
      final api = StubApi({});
      final svc = AdminService.test(api);
      await svc.decide('u1', approve: true);
      await svc.decide('u2', approve: false);
      expect(api.calls, ['POST /admin/verifications/u1', 'POST /admin/verifications/u2']);
      expect(api.bodies, [
        {'approve': true},
        {'approve': false},
      ]);
    });
  });
}
