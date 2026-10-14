import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hiring_app/models/app_user.dart';
import 'package:hiring_app/services/api_client.dart';
import 'package:hiring_app/services/auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/fake_api.dart';

http.Response json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('api_client_test_').path);
  });

  group('ApiClient', () {
    test('a dropped connection becomes a network error, not a crash', () async {
      final api = ApiClient.forTest(client: MockClient((_) async => throw http.ClientException('connection closed')));

      await expectLater(
        api.get('/jobs'),
        throwsA(isA<ApiException>().having((e) => e.isNetworkError, 'isNetworkError', isTrue)),
      );
    });

    test('a socket failure becomes a network error', () async {
      final api = ApiClient.forTest(client: MockClient((_) async => throw const SocketException('no route')));

      await expectLater(api.get('/jobs'), throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 0)));
    });

    test('a slow server times out with a readable message', () async {
      final api = ApiClient.forTest(
        timeout: const Duration(milliseconds: 40),
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          return json(200, {'ok': true});
        }),
      );

      await expectLater(
        api.get('/jobs'),
        throwsA(isA<ApiException>()
            .having((e) => e.isNetworkError, 'isNetworkError', isTrue)
            .having((e) => e.message, 'message', contains('too long'))),
      );
    });

    test('an HTML error page from a proxy is not shown as a parse error', () async {
      final api = ApiClient.forTest(
        client: MockClient((_) async => http.Response('<html>Bad gateway</html>', 502)),
      );

      await expectLater(
        api.get('/jobs'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 502)
            .having((e) => e.isServerError, 'isServerError', isTrue)
            .having((e) => e.message, 'message', isNot(contains('<html>')))),
      );
    });

    test('the backend error message is passed through', () async {
      final api = ApiClient.forTest(client: MockClient((_) async => json(400, {'error': 'Enter a valid phone number.'})));

      await expectLater(api.get('/x'), throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Enter a valid phone number.')));
    });

    test('a 401 on an authenticated call signs the session out, a wrong login does not', () async {
      var signedOut = 0;
      final api = ApiClient.forTest(
        client: MockClient((request) async {
          if (request.url.path == '/auth/login') return json(200, {'token': 't', 'firebaseToken': 'f', 'user': {}});
          return json(401, {'error': 'Invalid or expired token.'});
        }),
      )..onUnauthorized = () => signedOut++;

      await api.signIn(email: 'a@b.co', password: 'password123'); // saves a token
      await expectLater(api.get('/jobs'), throwsA(isA<ApiException>()));
      expect(signedOut, 1);

      // password confirmation for a sensitive action is a 401 that means "wrong password"
      await expectLater(api.reauth('wrong'), throwsA(isA<ApiException>()));
      expect(signedOut, 1);
    });

    test('fetchMe: null for an invalid session, an error when the server is down', () async {
      var status = 401;
      final api = ApiClient.forTest(
        client: MockClient((request) async {
          if (request.url.path == '/auth/login') return json(200, {'token': 't', 'firebaseToken': 'f', 'user': {}});
          return json(status, {'error': 'x'});
        }),
      );
      await api.signIn(email: 'a@b.co', password: 'password123');

      expect(await api.fetchMe(), isNull);

      status = 503;
      await expectLater(api.fetchMe(), throwsA(isA<ApiException>().having((e) => e.isServerError, 'isServerError', isTrue)));
    });
  });

  group('AuthService.fetchProfileWithRetry', () {
    AuthService serviceFor(ApiClient api) => AuthService.test(
          auth: MockFirebaseAuth(mockUser: MockUser(uid: 'u1', email: 'u@example.com'), signedIn: true),
          api: api,
        );

    test('retries a network failure and then succeeds', () async {
      final api = _FlakyApi(failures: 2);
      final profile = await serviceFor(api).fetchProfileWithRetry('u1', gap: Duration.zero);

      expect(api.calls, 3);
      expect(profile?.role, UserRole.recruiter);
    });

    test('gives up with the error instead of reporting a signed-out user', () async {
      final api = _FlakyApi(failures: 99);

      await expectLater(
        serviceFor(api).fetchProfileWithRetry('u1', attempts: 3, gap: Duration.zero),
        throwsA(isA<ApiException>().having((e) => e.isNetworkError, 'isNetworkError', isTrue)),
      );
      expect(api.calls, 3);
    });

    test('does not retry a rejection from the server', () async {
      final api = _FlakyApi(failures: 99, status: 400);

      await expectLater(serviceFor(api).fetchProfileWithRetry('u1', gap: Duration.zero), throwsA(isA<ApiException>()));
      expect(api.calls, 1);
    });

    test('a missing session is null, not an error', () async {
      final api = _FlakyApi(failures: 0)..account = null;

      expect(await serviceFor(api).fetchProfileWithRetry('u1', gap: Duration.zero), isNull);
    });
  });
}

/// Fails the first [failures] profile fetches the way a bad network does.
class _FlakyApi extends FakeApi {
  _FlakyApi({required this.failures, this.status = 0}) {
    account = {'uid': 'u1', 'email': 'u@example.com', 'name': 'U', 'role': 'recruiter', 'profileComplete': true};
  }

  final int failures;
  final int status;
  int calls = 0;

  @override
  Future<Map<String, dynamic>?> fetchMe() async {
    calls++;
    if (calls <= failures) throw ApiException(status, 'down');
    return account;
  }
}
