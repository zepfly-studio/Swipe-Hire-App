import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/models/chat_message.dart';
import 'package:hiring_app/models/opportunity.dart';

void main() {
  Map<String, dynamic> opportunityJson({Map<String, dynamic>? task, String status = 'taskAssigned'}) => {
        'id': 'opp-1',
        'candidateUid': 'cand-1',
        'candidateName': 'Cand One',
        'recruiterUid': 'rec-1',
        'recruiterName': 'Rec One',
        'companyName': 'Acme',
        'role': 'Flutter Developer',
        'jobPostingId': '',
        'status': status,
        'task': task,
      };

  Map<String, dynamic> taskJson({
    String status = 'assigned',
    String? dueDate,
    String? submittedAt,
    String feedback = '',
  }) =>
      {
        'id': 'task-1',
        'opportunityId': 'opp-1',
        'title': 'Build a login screen',
        'description': 'Use Flutter',
        'link': 'https://example.com/brief',
        'dueDate': dueDate,
        'status': status,
        'answer': '',
        'submissionLink': '',
        'submittedAt': submittedAt,
        'feedback': feedback,
        'reviewedAt': null,
      };

  group('Opportunity with a task', () {
    test('parses the new task statuses and the nested task', () {
      final o = Opportunity.fromMap('opp-1', opportunityJson(task: taskJson()));

      expect(o.status, OpportunityStatus.taskAssigned);
      expect(o.status.label, 'Task assigned');
      expect(o.task, isNotNull);
      expect(o.task!.title, 'Build a login screen');
      expect(o.task!.status, TaskStatus.assigned);
      expect(o.task!.link, 'https://example.com/brief');
    });

    test('has no task when the backend sends null, and unknown statuses fall back safely', () {
      final o = Opportunity.fromMap('opp-1', opportunityJson(status: 'somethingNew'));

      expect(o.task, isNull);
      expect(o.status, OpportunityStatus.shortlisted);
    });

    test('copyWithStatus keeps the task', () {
      final o = Opportunity.fromMap('opp-1', opportunityJson(task: taskJson(status: 'approved'), status: 'taskSubmitted'));

      final moved = o.copyWithStatus(OpportunityStatus.interviewScheduled);

      expect(moved.status, OpportunityStatus.interviewScheduled);
      expect(moved.task?.status, TaskStatus.approved);
    });

    test('toMap never sends the task back to the backend', () {
      final o = Opportunity.fromMap('opp-1', opportunityJson(task: taskJson()));
      expect(o.toMap().containsKey('task'), isFalse);
    });
  });

  group('OpportunityTask', () {
    test('isOverdue only while still waiting on the candidate and past due', () {
      final past = DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String();
      final future = DateTime.now().add(const Duration(days: 1)).toUtc().toIso8601String();

      expect(OpportunityTask.fromMap(taskJson(dueDate: past)).isOverdue, isTrue);
      expect(OpportunityTask.fromMap(taskJson(dueDate: future)).isOverdue, isFalse);
      expect(OpportunityTask.fromMap(taskJson(dueDate: past, status: 'submitted')).isOverdue, isFalse);
      expect(OpportunityTask.fromMap(taskJson()).isOverdue, isFalse);
    });

    test('wasSubmittedLate compares the submission time to the due date', () {
      final due = DateTime.utc(2026, 10, 20, 18);
      final onTime = OpportunityTask.fromMap(
        taskJson(status: 'submitted', dueDate: due.toIso8601String(), submittedAt: due.subtract(const Duration(hours: 2)).toIso8601String()),
      );
      final late = OpportunityTask.fromMap(
        taskJson(status: 'submitted', dueDate: due.toIso8601String(), submittedAt: due.add(const Duration(hours: 2)).toIso8601String()),
      );

      expect(onTime.wasSubmittedLate, isFalse);
      expect(late.wasSubmittedLate, isTrue);
    });

    test('hasChangeRequest is an assigned task that carries feedback', () {
      expect(OpportunityTask.fromMap(taskJson(feedback: 'Add an error state')).hasChangeRequest, isTrue);
      expect(OpportunityTask.fromMap(taskJson()).hasChangeRequest, isFalse);
      expect(OpportunityTask.fromMap(taskJson(status: 'approved', feedback: 'Nice')).hasChangeRequest, isFalse);
    });
  });

  group('ChatMessage kind', () {
    test('task and interview messages are system messages, plain text is not', () {
      expect(ChatMessage.fromMap('1', {'senderUid': 'a', 'text': 'hi'}).isSystem, isFalse);
      expect(ChatMessage.fromMap('2', {'senderUid': 'a', 'text': 'New task', 'kind': 'task'}).isSystem, isTrue);
      expect(ChatMessage.fromMap('3', {'senderUid': 'a', 'text': 'Interview', 'kind': 'interview'}).isSystem, isTrue);
    });
  });
}
