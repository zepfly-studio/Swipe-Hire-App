/// One entry in the in-app inbox (the bell). Backend: `notifications`.
class AppNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final String opportunityId;
  final bool read;
  final DateTime? createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    this.body = '',
    this.opportunityId = '',
    this.read = false,
    this.createdAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      id: map['id'] ?? '',
      type: map['type'] ?? 'info',
      title: map['title'] ?? '',
      body: map['body'] ?? '',
      opportunityId: map['opportunityId'] ?? '',
      read: map['read'] == true,
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '')?.toLocal(),
    );
  }

  AppNotification asRead() => AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        opportunityId: opportunityId,
        read: true,
        createdAt: createdAt,
      );
}

/// The two numbers the app's badges show.
class InboxSummary {
  final int unreadNotifications;
  final int unreadMessages;
  const InboxSummary({this.unreadNotifications = 0, this.unreadMessages = 0});

  factory InboxSummary.fromMap(Map<String, dynamic> map) => InboxSummary(
        unreadNotifications: (map['unreadNotifications'] as num?)?.toInt() ?? 0,
        unreadMessages: (map['unreadMessages'] as num?)?.toInt() ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      other is InboxSummary &&
      other.unreadNotifications == unreadNotifications &&
      other.unreadMessages == unreadMessages;

  @override
  int get hashCode => Object.hash(unreadNotifications, unreadMessages);
}
