import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/services/api_client.dart';
import 'package:hiring_app/services/hiring_task_service.dart';
import 'package:hiring_app/services/interview_service.dart';
import 'package:hiring_app/services/pair_chat_service.dart';
import 'package:hiring_app/services/pipeline_service.dart';

/// Records calls and answers from a path -> body map.
class _StubApi extends ApiClient {
  _StubApi(this.responses) : super.forTest();
  final Map<String, Map<String, dynamic>> responses;
  final List<String> calls = [];
  final List<Map<String, dynamic>?> bodies = [];
  final List<Map<String, String>?> queries = [];

  Map<String, dynamic> _answer(String method, String path, Map<String, dynamic>? body, Map<String, String>? query) {
    calls.add('$method $path');
    bodies.add(body);
    queries.add(query);
    return responses['$method $path'] ?? const {};
  }

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) async => _answer('GET', path, null, query);

  @override
  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body}) async => _answer('POST', path, body, null);

  @override
  Future<Map<String, dynamic>> patch(String path, {Map<String, dynamic>? body}) async =>
      _answer('PATCH', path, body, null);
}

void main() {
  test('shortlisted rows become candidates with swipe, job and contact', () async {
    final api = _StubApi({
      'GET /company/shortlisted': {
        'candidates': [
          {
            'id': 'u1',
            'name': 'Asha Rao',
            'swipeId': 's1',
            'stage': 'contacted',
            'notes': 'good',
            'job': {'id': 'j1', 'title': 'Flutter Dev'},
            'contact': {'email': 'a@b.co', 'phone': '999'},
          },
          {'name': 'No id'},
        ],
      },
    });
    final rows = await PipelineService.test(api).shortlisted(jobId: 'j1');
    expect(rows, hasLength(1));
    expect(rows.single.id, 'u1');
    expect(rows.single.swipeId, 's1');
    expect(rows.single.jobTitle, 'Flutter Dev');
    expect(rows.single.contactEmail, 'a@b.co');
    expect(api.queries.single, {'jobId': 'j1'});
  });

  test('setStage and setNotes patch the pipeline row', () async {
    final api = _StubApi({});
    final svc = PipelineService.test(api);
    await svc.setStage('s1', 'hired');
    await svc.setNotes('s1', 'hello');
    expect(api.calls, ['PATCH /company/pipeline/s1', 'PATCH /company/pipeline/s1']);
    expect(api.bodies, [
      {'stage': 'hired'},
      {'notes': 'hello'},
    ]);
  });

  test('bulk message sends ids and text, parses skipped', () async {
    final api = _StubApi({
      'POST /chats/bulk': {'sent': 1, 'skipped': ['u2']},
    });
    final res = await PairChatService.test(api).sendBulk(['u1', 'u2'], 'Hi');
    expect(api.bodies.single, {'text': 'Hi', 'candidateIds': ['u1', 'u2']});
    expect(res.sent, 1);
    expect(res.skipped, ['u2']);
  });

  test('conversations parse last message and unread', () async {
    final api = _StubApi({
      'GET /chats': {
        'conversations': [
          {
            'id': 'c1',
            'name': 'Acme',
            'verified': true,
            'stage': null,
            'unread': 2,
            'lastMessage': {'text': 'Hello', 'at': '2026-10-15T10:00:00Z', 'mine': false},
          },
        ],
      },
    });
    final list = await PairChatService.test(api).conversations();
    expect(list.single.person.verified, isTrue);
    expect(list.single.unread, 2);
    expect(list.single.lastText, 'Hello');
    expect(list.single.lastMine, isFalse);
    expect(list.single.stage, '');
  });

  test('task submit sends both links and note; deadline patches dueAt', () async {
    final api = _StubApi({});
    final svc = HiringTaskService.test(api);
    await svc.submit('t1', liveUrl: 'https://a.io', repoUrl: 'https://github.com/a/b', note: ' hi ');
    expect(api.bodies.last, {'liveUrl': 'https://a.io', 'repoUrl': 'https://github.com/a/b', 'note': 'hi'});
    await svc.changeDeadline('t1', DateTime.utc(2026, 10, 20, 12));
    expect(api.calls.last, 'PATCH /tasks/t1');
    expect(api.bodies.last, {'dueAt': '2026-10-20T12:00:00.000Z'});
    await svc.list(candidateId: 'u1');
    expect(api.queries.last, {'candidateId': 'u1'});
  });

  test('interview create sends only the fields for the chosen mode', () async {
    final api = _StubApi({
      'POST /interviews': {'id': 'i1'},
    });
    final svc = InterviewService.test(api);
    final id = await svc.create(
      candidateId: 'u1',
      slots: ['2026-10-16T05:30:00.000Z'],
      durationMins: 45,
      mode: 'in-person',
      location: ' Tower B ',
      meetingLink: 'https://ignored.example',
      note: '',
    );
    expect(id, 'i1');
    expect(api.bodies.single, {
      'candidateId': 'u1',
      'slots': ['2026-10-16T05:30:00.000Z'],
      'durationMins': 45,
      'mode': 'in-person',
      'location': 'Tower B',
    });
  });
}
