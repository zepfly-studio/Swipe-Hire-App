import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/models/app_user.dart';
import 'package:hiring_app/services/auth_service.dart';

import '../helpers/fake_api.dart';

void main() {
  group('AuthService', () {
    late MockFirebaseAuth auth;
    late FakeApi api;
    late AuthService service;

    setUp(() {
      auth = MockFirebaseAuth();
      api = FakeApi();
      service = AuthService.test(auth: auth, api: api);
    });

    test('signUp creates the backend account with the chosen role and signs into Firebase', () async {
      final profile = await service.signUp(
        name: 'Riya Shah',
        email: 'riya@example.com',
        password: 'password123',
        role: UserRole.candidate,
      );

      expect(profile.role, UserRole.candidate);
      expect(profile.name, 'Riya Shah');
      expect(api.account!['email'], 'riya@example.com');
      expect(auth.currentUser, isNotNull);
    });

    test('signIn surfaces a backend rejection as a FirebaseAuthException with its message', () async {
      expect(
        () => service.signIn(email: 'nobody@example.com', password: 'secret1'),
        throwsA(predicate((e) => e.toString().contains('Incorrect email or password.'))),
      );
      expect(auth.currentUser, isNull);
    });

    test('signIn signs into Firebase and returns the backend profile', () async {
      await service.signUp(name: 'Riya Shah', email: 'riya@example.com', password: 'password123', role: UserRole.recruiter);
      await auth.signOut();

      final profile = await service.signIn(email: 'riya@example.com', password: 'password123');

      expect(auth.currentUser, isNotNull);
      expect(profile.role, UserRole.recruiter);
      expect(profile.name, 'Riya Shah');
    });

    test('completeRecruiterProfile patches the backend profile and marks it complete', () async {
      await service.signUp(name: 'Rec One', email: 'rec@example.com', password: 'password123', role: UserRole.recruiter);

      await service.completeRecruiterProfile(designation: 'HR Lead', phone: '9999999999');

      expect(api.account!['designation'], 'HR Lead');
      expect(api.account!['phone'], '9999999999');
      expect(api.account!['profileComplete'], isTrue);
      expect((await service.fetchProfile(api.account!['uid'] as String))!.profileComplete, isTrue);
    });

    test('deleteAccount deletes the backend account (which cascades server-side) and signs out', () async {
      final signedUpUser = MockUser(uid: 'cand-1', email: 'cand@example.com');
      auth = MockFirebaseAuth(mockUser: signedUpUser, signedIn: true);
      service = AuthService.test(auth: auth, api: api);
      api.account = {'uid': 'cand-1', 'email': 'cand@example.com', 'name': 'Cand One', 'role': 'candidate'};

      await service.deleteAccount();

      expect(api.deleted, isTrue);
      expect(api.account, isNull);
      expect(auth.currentUser, isNull);
    });
  });
}
