import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/models/job_posting.dart';
import 'package:hiring_app/services/job_posting_service.dart';

import '../helpers/fake_api.dart';

void main() {
  group('JobPostingService', () {
    late FakeApi api;
    late JobPostingService service;

    JobPosting posting({String id = '', String recruiterUid = 'rec-1', bool isOpen = true}) {
      return JobPosting(
        id: id,
        recruiterUid: recruiterUid,
        recruiterName: 'Rec One',
        companyName: 'Acme',
        title: 'Flutter Dev',
        description: 'Build things',
        skills: const ['Flutter', 'Dart'],
        location: 'Remote',
        employmentType: 'Full-time',
        isOpen: isOpen,
        createdAt: DateTime.now(),
      );
    }

    void signInAs(String uid, String role) {
      api.account = {'uid': uid, 'email': '$uid@example.com', 'name': uid, 'role': role};
    }

    setUp(() {
      api = FakeApi();
      service = JobPostingService.test(api);
    });

    test('create publishes under the signed-in recruiter and streamMyPostings returns it', () async {
      signInAs('rec-1', 'recruiter');

      final id = await service.create(posting());

      expect(id, isNotEmpty);
      final mine = await service.streamMyPostings('rec-1').first;
      expect(mine, hasLength(1));
      expect(mine.first.recruiterUid, 'rec-1');
      expect(mine.first.title, 'Flutter Dev');
    });

    test('apply creates an opportunity with status applied for the signed-in candidate', () async {
      signInAs('rec-1', 'recruiter');
      final id = await service.create(posting());
      signInAs('cand-1', 'candidate');

      await service.apply(posting: posting(id: id), candidateUid: 'cand-1', candidateName: 'Cand One');

      expect(api.opportunities, hasLength(1));
      expect(api.opportunities.first['status'], 'applied');
      expect(api.opportunities.first['candidateUid'], 'cand-1');
      expect(api.opportunities.first['recruiterUid'], 'rec-1');
    });

    test('hasApplied is true only after apply() for that exact candidate+posting', () async {
      signInAs('rec-1', 'recruiter');
      final id = await service.create(posting());
      signInAs('cand-1', 'candidate');
      expect(await service.hasApplied('cand-1', id), isFalse);

      await service.apply(posting: posting(id: id), candidateUid: 'cand-1', candidateName: 'Cand One');

      expect(await service.hasApplied('cand-1', id), isTrue);
      signInAs('cand-2', 'candidate');
      expect(await service.hasApplied('cand-2', id), isFalse);
    });

    test('saveJob / unsaveJob / streamSavedJobIds round-trip', () async {
      signInAs('cand-1', 'candidate');
      await service.saveJob('cand-1', 'job-1');
      await service.saveJob('cand-1', 'job-2');

      final saved = await service.streamSavedJobIds('cand-1').first;
      expect(saved, {'job-1', 'job-2'});

      await service.unsaveJob('cand-1', 'job-1');
      final afterUnsave = await service.streamSavedJobIds('cand-1').first;
      expect(afterUnsave, {'job-2'});
    });

    test('streamOpenPostings only returns postings with isOpen true', () async {
      signInAs('rec-1', 'recruiter');
      await service.create(posting(isOpen: true));
      final closedId = await service.create(posting());
      await service.setOpen(closedId, false);

      final open = await service.streamOpenPostings().first;
      expect(open, hasLength(1));
      expect(open.first.isOpen, isTrue);
    });
  });
}
