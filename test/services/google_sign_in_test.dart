import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/models/app_user.dart';
import 'package:hiring_app/services/auth_service.dart';

import '../helpers/fake_api.dart';

void main() {
  group('AuthService.signInWithGoogle', () {
    late MockFirebaseAuth auth;
    late FakeApi api;
    late AuthService service;

    setUp(() {
      auth = MockFirebaseAuth();
      api = FakeApi();
      service = AuthService.test(auth: auth, api: api);
    });

    test('closing the Google window returns null and calls nothing', () async {
      service.googleIdTokenProvider = () async => null;

      expect(await service.signInWithGoogle(), isNull);
      expect(api.googleIdToken, isNull);
      expect(auth.currentUser, isNull);
    });

    test('a first-time account is asked for a role', () async {
      service.googleIdTokenProvider = () async => 'google-id-token';

      await expectLater(service.signInWithGoogle(), throwsA(isA<GoogleSignInNeedsRole>()));
      expect(api.googleIdToken, 'google-id-token');
      expect(auth.currentUser, isNull);
    });

    test('with a role it signs into Firebase and returns the backend profile', () async {
      service.googleIdTokenProvider = () async => 'google-id-token';

      final user = await service.signInWithGoogle(role: UserRole.candidate);

      expect(api.googleRole, 'candidate');
      expect(user!.role, UserRole.candidate);
      expect(user.name, 'Google User');
      expect(auth.currentUser, isNotNull);
    });
  });
}
