import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/services/api_client.dart';
import 'package:hiring_app/services/team_service.dart';

class _StubApi extends ApiClient {
  _StubApi(this.responses) : super.forTest();
  final Map<String, Map<String, dynamic>> responses;
  final List<String> calls = [];
  final List<Map<String, dynamic>?> bodies = [];

  Map<String, dynamic> _answer(String method, String path, Map<String, dynamic>? body) {
    calls.add('$method $path');
    bodies.add(body);
    return responses['$method $path'] ?? const {};
  }

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) async => _answer('GET', path, null);

  @override
  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body}) async => _answer('POST', path, body);

  @override
  Future<Map<String, dynamic>> delete(String path) async => _answer('DELETE', path, null);
}

void main() {
  group('extractInviteToken', () {
    test('bare code is trimmed', () {
      expect(extractInviteToken('  abc_DEF-123  \n'), 'abc_DEF-123');
    });
    test('whitespace inside a wrapped paste is removed', () {
      expect(extractInviteToken('abc DEF\n123'), 'abcDEF123');
    });
    test('link with token query', () {
      expect(extractInviteToken('https://swipehire.app/join?token=abc_DEF-123'), 'abc_DEF-123');
      expect(extractInviteToken('https://x.io/join?ref=1&token=tok42&utm=a'), 'tok42');
    });
    test('empty input', () {
      expect(extractInviteToken('   '), '');
    });
  });

  group('TeamData', () {
    final data = TeamData.fromMap({
      'isOwner': true,
      'members': [
        {'id': 'u1', 'name': 'Asha Rao', 'email': 'a@b.co', 'role': 'owner', 'you': true},
        {'id': 'u2', 'name': '', 'email': 'sam.k@b.co', 'role': 'recruiter', 'you': false},
        'junk',
      ],
      'invites': [
        {'id': 'i1', 'email': 'new@b.co', 'expires': '2030-01-01'},
      ],
    });

    test('parses members and invites', () {
      expect(data.isOwner, isTrue);
      expect(data.members, hasLength(2));
      expect(data.members.first.isOwner, isTrue);
      expect(data.members.first.isYou, isTrue);
      expect(data.members.last.isOwner, isFalse);
      expect(data.invites.single.email, 'new@b.co');
    });

    test('size counts members and pending invites against the limit', () {
      expect(data.size, 3);
      expect(data.seatsLeft, kMaxTeamSize - 3);
      expect(data.isFull, isFalse);
      final full = TeamData(
        isOwner: true,
        members: [for (var i = 0; i < 8; i++) TeamMember(id: '$i', name: 'n', email: '', isOwner: i == 0, isYou: false)],
        invites: const [TeamInvite(id: 'a', email: 'a@b.co'), TeamInvite(id: 'b', email: 'b@b.co')],
      );
      expect(full.isFull, isTrue);
      expect(full.seatsLeft, 0);
    });

    test('initials fall back to the email', () {
      expect(data.members.first.initials, 'AR');
      expect(data.members.last.displayName, 'sam.k@b.co');
      expect(data.members.last.initials, 'SK');
      expect(initialsOf(''), '?');
    });
  });

  group('TeamService', () {
    test('load reads GET /team', () async {
      final api = _StubApi({
        'GET /team': {'isOwner': false, 'members': [], 'invites': []},
      });
      final data = await TeamService.test(api).load();
      expect(api.calls, ['GET /team']);
      expect(data.isOwner, isFalse);
    });

    test('invite posts the trimmed email and returns the code when present', () async {
      final api = _StubApi({
        'POST /team/invite': {'ok': true, 'inviteCode': 'CODE123'},
      });
      final res = await TeamService.test(api).invite('  x@y.co ');
      expect(api.calls, ['POST /team/invite']);
      expect(api.bodies.single, {'email': 'x@y.co'});
      expect(res.inviteCode, 'CODE123');
    });

    test('invite without a code', () async {
      final api = _StubApi({
        'POST /team/invite': {'ok': true},
      });
      expect((await TeamService.test(api).invite('x@y.co')).inviteCode, isNull);
    });

    test('remove member and cancel invite hit the right DELETE routes', () async {
      final api = _StubApi({});
      final svc = TeamService.test(api);
      await svc.removeMember('u2');
      await svc.cancelInvite('i1');
      expect(api.calls, ['DELETE /team/members/u2', 'DELETE /team/invites/i1']);
    });
  });
}
