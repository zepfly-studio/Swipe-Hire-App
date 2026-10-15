import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/models/candidate.dart';
import 'package:hiring_app/models/pair/chat_models.dart';
import 'package:hiring_app/models/pair/hiring_task.dart';
import 'package:hiring_app/models/pair/interview.dart';
import 'package:hiring_app/models/pair/notification_link.dart';
import 'package:hiring_app/models/pair/pair_format.dart';
import 'package:hiring_app/models/pair/pair_person.dart';
import 'package:hiring_app/models/pair/pipeline_models.dart';
import 'package:hiring_app/models/pair/pipeline_stage.dart';

Candidate _cand(String id, {String swipeId = '', String stage = 'shortlisted', String jobId = 'j1'}) =>
    Candidate.fromMap(id, {
      'name': 'Person $id',
      'swipeId': swipeId,
      'stage': stage,
      'job': {'id': jobId, 'title': 'Job $jobId'},
    });

void main() {
  group('stage mapping', () {
    test('company labels', () {
      expect(stageLabel('task'), 'Task sent');
      expect(stageLabel('hired'), 'Hired');
      expect(stageLabel('rejected'), 'Rejected');
      expect(stageLabel(''), 'Shortlisted');
    });

    test('candidate labels hide rejection', () {
      expect(candidateStageLabel('hired'), contains('Selected'));
      expect(candidateStageLabel('rejected'), 'Closed');
      expect(candidateStageLabel('closed'), 'Closed');
      expect(candidateStageLabel('interview'), 'Interview');
    });

    test('counts per tab, unknown stage counts as shortlisted', () {
      final counts = stageCounts(['shortlisted', 'contacted', 'contacted', 'hired', 'weird']);
      expect(counts['all'], 5);
      expect(counts['shortlisted'], 2);
      expect(counts['contacted'], 2);
      expect(counts['hired'], 1);
      expect(counts['rejected'], 0);
    });
  });

  group('task status', () {
    final now = DateTime(2026, 10, 15, 12);
    HiringTask task(String status, DateTime due) => HiringTask(
          id: status,
          person: const PairPerson(id: 'c', name: 'C'),
          title: 't',
          status: status,
          dueAt: due,
        );

    test('assigned past its deadline is overdue; submitted stays submitted', () {
      expect(task('assigned', now.subtract(const Duration(hours: 1))).effectiveStatus(now), 'overdue');
      expect(task('assigned', now.add(const Duration(hours: 1))).effectiveStatus(now), 'assigned');
      expect(task('submitted', now.subtract(const Duration(days: 1))).effectiveStatus(now), 'submitted');
    });

    test('labels and filter counts', () {
      expect(taskStatusLabel('overdue'), 'Deadline passed');
      expect(taskStatusLabel('assigned'), 'Waiting');
      final tasks = [
        task('assigned', now.add(const Duration(days: 1))),
        task('assigned', now.subtract(const Duration(days: 1))),
        task('submitted', now),
        task('cancelled', now),
      ];
      final counts = taskFilterCounts(tasks, now: now);
      expect(counts, {'all': 4, 'assigned': 1, 'submitted': 1, 'overdue': 1});
      expect(filterTasks(tasks, 'overdue', now: now), hasLength(1));
    });

    test('canSubmit only before the deadline', () {
      expect(task('assigned', now.add(const Duration(hours: 2))).canSubmit(now), isTrue);
      expect(task('submitted', now.add(const Duration(hours: 2))).canSubmit(now), isTrue);
      expect(task('assigned', now.subtract(const Duration(hours: 2))).canSubmit(now), isFalse);
      expect(task('cancelled', now.add(const Duration(hours: 2))).canSubmit(now), isFalse);
    });
  });

  group('time left', () {
    final now = DateTime(2026, 10, 15, 12);
    test('days and hours', () {
      expect(timeLeftLabel(now.add(const Duration(days: 2, hours: 4, minutes: 10)), now: now), '2 days 4 h left');
      expect(timeLeftLabel(now.add(const Duration(days: 1, hours: 1)), now: now), '1 day 1 h left');
      expect(timeLeftLabel(now.add(const Duration(days: 3)), now: now), '3 days left');
    });
    test('hours, minutes and passed', () {
      expect(timeLeftLabel(now.add(const Duration(hours: 5, minutes: 20)), now: now), '5 h left');
      expect(timeLeftLabel(now.add(const Duration(minutes: 45)), now: now), '45 min left');
      expect(timeLeftLabel(now.add(const Duration(seconds: 10)), now: now), '1 min left');
      expect(timeLeftLabel(now.subtract(const Duration(minutes: 1)), now: now), 'Deadline passed');
    });
    test('urgent only under an hour', () {
      expect(isTimeLeftUrgent(now.add(const Duration(minutes: 30)), now: now), isTrue);
      expect(isTimeLeftUrgent(now.add(const Duration(hours: 2)), now: now), isFalse);
      expect(isTimeLeftUrgent(now.subtract(const Duration(hours: 1)), now: now), isFalse);
    });
    test('formatting', () {
      final d = DateTime(2026, 10, 5, 23, 59); // a Monday
      expect(formatPairDateTime(d), 'Mon, 5 Oct, 11:59 pm');
      expect(formatPairClock(DateTime(2026, 1, 1, 0, 5)), '12:05 am');
    });
  });

  group('task links', () {
    const bad = 'bad';
    test('https is added when the scheme is missing', () {
      expect(checkTaskLink('my-app.vercel.app', invalidMessage: bad).url, 'https://my-app.vercel.app');
      expect(checkTaskLink('http://x.io/a', invalidMessage: bad).url, 'http://x.io/a');
      expect(checkTaskLink('  ', invalidMessage: bad).url, '');
    });
    test('rejects other schemes, bad hosts and overlong links', () {
      expect(checkTaskLink('javascript:alert(1)', invalidMessage: bad).error, bad);
      expect(checkTaskLink('ftp://x.io', invalidMessage: bad).error, bad);
      expect(checkTaskLink('mailto:a@b.co', invalidMessage: bad).error, bad);
      expect(checkTaskLink('nodots', invalidMessage: bad).error, bad);
      expect(checkTaskLink('a.io/${'x' * 300}', invalidMessage: bad).error, bad);
    });
    test('repo must be on github.com', () {
      expect(checkTaskLink('github.com/me/app', githubOnly: true, invalidMessage: bad).url, 'https://github.com/me/app');
      expect(checkTaskLink('https://www.github.com/me/app', githubOnly: true, invalidMessage: bad).isOk, isTrue);
      expect(
        checkTaskLink('gitlab.com/me/app', githubOnly: true, invalidMessage: bad).error,
        'The repo link must be a github.com link',
      );
      expect(checkTaskLink('notgithub.com/x', githubOnly: true, invalidMessage: bad).isOk, isFalse);
    });
    test('submission needs at least one link', () {
      expect(validateSubmission(live: '', repo: '').formError, 'Add your live link or GitHub repo link');
      final ok = validateSubmission(live: 'my-app.vercel.app', repo: '');
      expect(ok.isValid, isTrue);
      expect(ok.liveUrl, 'https://my-app.vercel.app');
      expect(ok.repoUrl, '');
      expect(validateSubmission(live: '', repo: 'gitlab.com/a/b').repoError, isNotNull);
      expect(validateSubmission(live: 'javascript:1', repo: 'github.com/a/b').liveError, 'Please enter a valid live link');
    });
    test('deadline window', () {
      final now = DateTime(2026, 10, 15, 12);
      expect(validateTaskDeadline(now.add(const Duration(minutes: 30)), now: now), isNotNull);
      expect(validateTaskDeadline(now.add(const Duration(days: 3)), now: now), isNull);
      expect(validateTaskDeadline(now.add(const Duration(days: 31)), now: now), 'The deadline can be at most 30 days away');
      expect(validateTaskDeadline(null, now: now), isNotNull);
      expect(deadlinePreset(3, now: now), DateTime(2026, 10, 18, 23, 59));
    });
  });

  group('interviews', () {
    final now = DateTime(2026, 10, 15, 12);

    test('default slots are tomorrow and the day after at 11:00', () {
      final slots = defaultInterviewSlots(now);
      expect(slots, [DateTime(2026, 10, 16, 11), DateTime(2026, 10, 17, 11)]);
    });

    test('form validation', () {
      String? v(List<DateTime?> s, {String mode = 'video', String loc = ''}) =>
          validateInterviewForm(slots: s, mode: mode, location: loc, now: now);
      expect(v([]), 'Add at least one time slot');
      expect(v([null]), 'Add at least one time slot');
      expect(v([now.add(const Duration(minutes: 10))]), 'Time slots must be in the future');
      expect(v([now.add(const Duration(minutes: 15))]), isNull);
      expect(v([now.add(const Duration(days: 1))], mode: 'in-person'), 'Please add the interview address');
      expect(v([now.add(const Duration(days: 1))], mode: 'in-person', loc: 'Tower B'), isNull);
    });

    test('slots are de-duplicated, sorted and sent as UTC ISO', () {
      final a = DateTime.utc(2026, 10, 16, 6);
      final b = DateTime.utc(2026, 10, 17, 6);
      expect(slotsToIso([b, a, a, null]), [a.toIso8601String(), b.toIso8601String()]);
    });

    Interview iv(String id, String status, {DateTime? chosen, DateTime? created}) => Interview(
          id: id,
          person: const PairPerson(id: 'p', name: 'P'),
          status: status,
          chosenSlot: chosen,
          durationMins: 30,
          createdAt: created,
        );

    test('grouping and status labels', () {
      final groups = groupInterviews([
        iv('p', 'proposed', created: now),
        iv('soon', 'confirmed', chosen: now.add(const Duration(days: 2))),
        iv('sooner', 'confirmed', chosen: now.add(const Duration(days: 1))),
        iv('done', 'confirmed', chosen: now.subtract(const Duration(days: 1))),
        iv('x', 'cancelled'),
      ], now: now);
      expect(groups.pending.map((i) => i.id), ['p']);
      expect(groups.upcoming.map((i) => i.id), ['sooner', 'soon']);
      expect(groups.past.map((i) => i.id).toSet(), {'done', 'x'});

      expect(interviewStatusLabel(iv('a', 'proposed'), isCompany: true), 'Waiting for reply');
      expect(interviewStatusLabel(iv('a', 'proposed'), isCompany: false), 'Pick a time');
      expect(interviewStatusLabel(iv('a', 'confirmed', chosen: now.add(const Duration(days: 1))), isCompany: false, now: now), 'Confirmed');
      expect(interviewStatusLabel(iv('a', 'confirmed', chosen: now.subtract(const Duration(days: 1))), isCompany: false, now: now), 'Done');
      expect(interviewStatusLabel(iv('a', 'cancelled'), isCompany: true), 'Cancelled');
    });

    test('calendar link', () {
      final i = Interview(
        id: '1',
        person: const PairPerson(id: 'p', name: 'Acme'),
        chosenSlot: DateTime.utc(2026, 10, 20, 9, 30),
        durationMins: 45,
        status: 'confirmed',
        meetingLink: 'https://meet.jit.si/SwipeHire-abc',
        note: 'Bring portfolio',
      );
      final uri = interviewCalendarUri(i, title: 'Interview: Acme');
      expect(uri.host, 'calendar.google.com');
      expect(uri.queryParameters['action'], 'TEMPLATE');
      expect(uri.queryParameters['text'], 'Interview: Acme');
      expect(uri.queryParameters['dates'], '20261020T093000Z/20261020T101500Z');
      expect(uri.queryParameters['location'], 'https://meet.jit.si/SwipeHire-abc');
    });
  });

  group('group selection', () {
    test('dedupes by person, keeping order', () {
      final rows = [_cand('a', swipeId: 's1', jobId: 'j1'), _cand('b', swipeId: 's2'), _cand('a', swipeId: 's3', jobId: 'j2')];
      expect(dedupeByPerson(rows).map((c) => c.id), ['a', 'b']);
    });

    test('selecting a person selects them once across jobs', () {
      final rows = [_cand('a', swipeId: 's1', jobId: 'j1'), _cand('a', swipeId: 's3', jobId: 'j2'), _cand('b', swipeId: 's2')];
      final sel = PipelineSelection();
      expect(sel.headerLabel(2), 'Select all');
      expect(sel.buttonLabel(2), 'Message all (2)');
      expect(sel.recipients(rows).map((c) => c.id), ['a', 'b']);
      sel.toggle('a');
      expect(sel.count, 1);
      expect(sel.headerLabel(2), '1 selected');
      expect(sel.buttonLabel(2), 'Message 1 selected');
      expect(sel.recipients(rows).map((c) => c.id), ['a']);
      sel.selectAll(rows);
      expect(sel.count, 2);
      sel.retainOnly([rows[2]]);
      expect(sel.ids, {'b'});
      sel.clear();
      expect(sel.isEmpty, isTrue);
    });

    test('stage filter and job labels', () {
      final rows = [_cand('a', stage: 'contacted'), _cand('b', stage: 'hired'), _cand('c', stage: '')];
      expect(rowsInStage(rows, 'all'), hasLength(3));
      expect(rowsInStage(rows, 'contacted').single.id, 'a');
      expect(rowsInStage(rows, 'shortlisted').single.id, 'c');
      expect(const PipelineJob(id: '1', title: 'Dev', status: 'paused').filterLabel, 'Dev (paused)');
      expect(const PipelineJob(id: '1', title: 'Dev', status: 'closed').filterLabel, 'Dev (closed)');
      expect(const PipelineJob(id: '1', title: 'Dev').filterLabel, 'Dev');
    });
  });

  group('notification link routing', () {
    test('messages with id', () {
      expect(parseNotificationLink('/messages?with=abc'),
          const NotificationTarget(NotificationTargetKind.messages, 'abc'));
      expect(parseNotificationLink('/messages').param, isNull);
    });
    test('simple routes', () {
      expect(parseNotificationLink('/interviews').kind, NotificationTargetKind.interviews);
      expect(parseNotificationLink('/tasks').kind, NotificationTargetKind.tasks);
      expect(parseNotificationLink('/candidate').kind, NotificationTargetKind.candidateHome);
      expect(parseNotificationLink('/company/shortlisted').kind, NotificationTargetKind.shortlisted);
      expect(parseNotificationLink('/company/verify').kind, NotificationTargetKind.verify);
    });
    test('swipe search id', () {
      expect(parseNotificationLink('/company/swipe?search=s9'),
          const NotificationTarget(NotificationTargetKind.swipe, 's9'));
    });
    test('unknown and empty', () {
      expect(parseNotificationLink('').kind, NotificationTargetKind.unknown);
      expect(parseNotificationLink(null).kind, NotificationTargetKind.unknown);
      expect(parseNotificationLink('/nope').kind, NotificationTargetKind.unknown);
    });
  });

  group('chat models', () {
    test('conversation tolerates missing fields and null stage', () {
      final c = PairConversation.fromMap({'id': 'u1', 'name': 'Acme', 'stage': null});
      expect(c.person.id, 'u1');
      expect(c.stage, '');
      expect(c.unread, 0);
      expect(c.lastText, '');
    });

    test('day breaks mark the first message of each day', () {
      PairMessage m(DateTime d) => PairMessage(id: '$d', text: 't', mine: true, at: d);
      final msgs = [
        m(DateTime(2026, 10, 14, 9)),
        m(DateTime(2026, 10, 14, 18)),
        m(DateTime(2026, 10, 15, 9)),
      ];
      expect(dayBreaks(msgs), [true, false, true]);
    });

    test('conversation time', () {
      final now = DateTime(2026, 10, 15, 12);
      expect(conversationTime(null, now: now), 'new');
      expect(conversationTime(now.subtract(const Duration(minutes: 5)), now: now), '5m');
      expect(conversationTime(now.subtract(const Duration(hours: 3)), now: now), '3h');
      expect(conversationTime(DateTime(2026, 10, 14, 20), now: now), 'Yesterday');
    });
  });
}
