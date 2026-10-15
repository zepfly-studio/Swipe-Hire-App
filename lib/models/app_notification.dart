/// One entry in the in-app inbox (the bell). Backend: `notifications`.
class AppNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final String opportunityId;

  /// The website route this notification leads to (`/messages?with=<id>`,
  /// `/interviews`, `/tasks`...); empty when it has none.
  final String link;
  final bool read;
  final DateTime? createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    this.body = '',
    this.opportunityId = '',
    this.link = '',
    this.read = false,
    this.createdAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      id: (map['id'] ?? '').toString(),
      type: (map['type'] ?? 'info').toString(),
      title: (map['title'] ?? '').toString(),
      body: (map['body'] ?? '').toString(),
      opportunityId: (map['opportunityId'] ?? '').toString(),
      link: (map['link'] ?? '').toString(),
      read: map['read'] == true,
      createdAt: DateTime.tryParse((map['createdAt'] ?? map['at'] ?? '').toString())?.toLocal(),
    );
  }

  AppNotification asRead() => AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        opportunityId: opportunityId,
        link: link,
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
