import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/models/opportunity.dart';
import 'package:hiring_app/screens/candidate/task_submit_screen.dart';
import 'package:hiring_app/services/opportunity_service.dart';
import 'package:hiring_app/theme/app_theme.dart';
import 'package:hiring_app/widgets/app_toast.dart';

import '../helpers/fake_api.dart';

/// Records the submit call and answers like the backend does: the opportunity
/// back, with the task now "submitted" and carrying what was sent.
class _SubmitApi extends FakeApi {
  Map<String, dynamic>? lastBody;
  String? lastPath;

  @override
  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body}) async {
    if (path.endsWith('/submit')) {
      lastPath = path;
      lastBody = body;
      return {
        'opportunity': {
          ..._opportunityJson,
          'status': 'taskSubmitted',
          'task': {
            ..._taskJson,
            'status': 'submitted',
            'answer': body?['answer'] ?? '',
            'submissionLink': body?['link'] ?? '',
            'submittedAt': DateTime.now().toUtc().toIso8601String(),
          },
        },
      };
    }
    return super.post(path, body: body);
  }
}

const _taskJson = <String, dynamic>{
  'id': 'task-1',
  'opportunityId': 'opp-1',
  'title': 'Build a login screen',
  'description': 'Use Flutter and show validation errors.',
  'link': '',
  'dueDate': null,
  'status': 'assigned',
  'answer': '',
  'submissionLink': '',
  'submittedAt': null,
  'feedback': '',
  'reviewedAt': null,
};

const _opportunityJson = <String, dynamic>{
  'id': 'opp-1',
  'candidateUid': 'cand-1',
  'candidateName': 'Cand One',
  'recruiterUid': 'rec-1',
  'recruiterName': 'Rec One',
  'companyName': 'Acme',
  'role': 'Flutter Developer',
  'jobPostingId': '',
  'status': 'taskAssigned',
  'task': _taskJson,
};

void main() {
  late _SubmitApi api;

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      builder: AppToastHost.builder,
      home: TaskSubmitScreen(
        opportunity: Opportunity.fromMap('opp-1', Map<String, dynamic>.from(_opportunityJson)),
        service: OpportunityService.test(api),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
  }

  setUp(() => api = _SubmitApi());

  testWidgets('submitting shows the Submitted popup and clears the form', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Submit task'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Your answer or notes'), 'Here is my login screen.');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Link to your work (GitHub, Drive, Figma, video)'),
      'https://github.com/example/login',
    );
    await tester.tap(find.text('Submit task'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // What went to the backend.
    expect(api.lastPath, '/opportunities/opp-1/tasks/task-1/submit');
    expect(api.lastBody, {
      'answer': 'Here is my login screen.',
      'link': 'https://github.com/example/login',
      'fileUrl': '',
      'fileName': '',
    });

    // The popup.
    expect(find.text('Task submitted'), findsOneWidget);
    expect(find.textContaining('Acme'), findsWidgets);

    await tester.tap(find.text('Done'));
    await tester.pump(const Duration(milliseconds: 400));

    // The form is gone and nothing is left typed in it; the work is shown
    // read-only with an Edit button instead.
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Submit task'), findsNothing);
    expect(find.text('Edit submission'), findsOneWidget);
    expect(find.text('Here is my login screen.'), findsOneWidget);
  });

  testWidgets('an empty form is not sent', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Submit task'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.lastPath, isNull);
    expect(find.text('Task submitted'), findsNothing);
    expect(find.text('Add your answer, a link, or a file.'), findsOneWidget);
  });

  testWidgets('Edit submission reopens the form with the previous answer', (tester) async {
    await pumpScreen(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'Your answer or notes'), 'First draft');
    await tester.tap(find.text('Submit task'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Done'));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Edit submission'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Update submission'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'First draft'), findsOneWidget);
  });
}
