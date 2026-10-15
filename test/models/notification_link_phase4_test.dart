import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/models/pair/notification_link.dart';

void main() {
  test('/company/verify opens the verification screen', () {
    expect(parseNotificationLink('/company/verify').kind, NotificationTargetKind.verify);
    expect(parseNotificationLink('/company/verify/').kind, NotificationTargetKind.verify);
  });

  test('/company/team opens the team screen', () {
    expect(parseNotificationLink('/company/team').kind, NotificationTargetKind.team);
    expect(parseNotificationLink('/company/team?x=1').kind, NotificationTargetKind.team);
    expect(parseNotificationLink('/company/teams').kind, NotificationTargetKind.unknown);
  });
}
