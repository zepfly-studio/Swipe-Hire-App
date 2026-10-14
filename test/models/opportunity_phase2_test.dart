import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/models/app_notification.dart';
import 'package:hiring_app/models/opportunity.dart';
import 'package:hiring_app/services/candidate_service.dart';
import 'package:hiring_app/services/in_app_notifier.dart';
import 'package:hiring_app/services/job_posting_service.dart';

Map<String, dynamic> _task(String id, String status, {String feedback = ''}) => {
      'id': id,
      'opportunityId': 'opp-1',
      'title': 'Task $id',
      'status': status,
      'feedback': feedback,
    };

void main() {
  group('Opportunity with several tasks', () {
    final map = <String, dynamic>{
      'candidateUid': 'c',
      'candidateName': 'Cand',
      'recruiterUid': 'r',
      'recruiterName': 'Rec',
      'companyName': 'Acme',
      'companyVerified': true,
      'role': 'Dev',
      'status': 'taskAssigned',
      'interviewResponse': 'reschedule_requested',
      'interviewResponseNote': 'Can we do the afternoon?',
      'offerResponse': 'accepted',
      'unreadCount': 3,
      'task': _task('a', 'assigned'),
      'tasks': [_task('a', 'assigned'), _task('b', 'submitted'), _task('c', 'approved')],
    };

    test('separates what the candidate owes from what the recruiter must review', () {
      final o = Opportunity.fromMap('opp-1', map);

      expect(o.tasks, hasLength(3));
      expect(o.pendingTasks.map((t) => t.id), ['a']);
      expect(o.tasksToReview.map((t) => t.id), ['b']);
      expect(o.task!.id, 'a');
    });

    test('reads the responses, unread count and verified flag', () {
      final o = Opportunity.fromMap('opp-1', map);

      expect(o.interviewResponse, InterviewResponse.rescheduleRequested);
      expect(o.interviewResponseNote, 'Can we do the afternoon?');
      expect(o.offerResponse, 'accepted');
      expect(o.unreadCount, 3);
      expect(o.companyVerified, isTrue);
    });

    test('a response with only one task still gives a task list', () {
      final o = Opportunity.fromMap('opp-1', {...map, 'tasks': null, 'task': _task('solo', 'assigned')});
      expect(o.tasks.map((t) => t.id), ['solo']);
    });

    test('withdrawn is a closed status the recruiter cannot pick', () {
      expect(OpportunityStatusX.fromString('withdrawn'), OpportunityStatus.withdrawn);
      expect(OpportunityStatus.withdrawn.isClosed, isTrue);
      expect(OpportunityStatus.withdrawn.isManual, isFalse);
      expect(OpportunityStatus.taskAssigned.isManual, isFalse);
      expect(OpportunityStatus.shortlisted.isManual, isTrue);
    });
  });

  group('unseenNotifications', () {
    AppNotification n(String id, {bool read = false}) => AppNotification(id: id, type: 'info', title: id, read: read);

    test('keeps only unread, unseen ones and puts the oldest first', () {
      final fresh = unseenNotifications(
        seen: {'old'},
        fetched: [n('new2'), n('new1'), n('old'), n('done', read: true)],
      );
      expect(fresh.map((e) => e.id), ['new1', 'new2']);
    });

    test('nothing new gives an empty list', () {
      expect(unseenNotifications(seen: {'a'}, fetched: [n('a')]), isEmpty);
    });
  });

  group('filters', () {
    test('candidate filters send only what is set', () {
      expect(const CandidateFilters().toQuery(), isEmpty);
      final q = const CandidateFilters(
        query: ' flutter ',
        skills: ['Dart', 'Firebase'],
        location: 'Pune',
        expMin: 2,
        ctcMax: 18,
        noticeMaxDays: 30,
        jobId: 'job-1',
        sortByMatch: true,
      ).toQuery();
      expect(q, {
        'q': 'flutter',
        'skills': 'Dart,Firebase',
        'location': 'Pune',
        'expMin': '2.0',
        'ctcMax': '18.0',
        'noticeMax': '30',
        'jobId': 'job-1',
        'sort': 'match',
      });
    });

    test('job filters count what is on, not the search text or sort', () {
      const f = JobFilters(query: 'dev', location: 'Remote', remoteOnly: true, sortByMatch: true);
      expect(f.activeCount, 2);
      expect(f.toQuery(), {'q': 'dev', 'location': 'Remote', 'remote': '1', 'sort': 'match'});
      expect(const JobFilters().isEmpty, isTrue);
    });
  });
}
