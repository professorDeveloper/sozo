/// What a viewer's request to support is about. The server keeps the same
/// list (models/SupportTicket.js); a value it does not know is refused.
enum SupportCategory { playback, account, content, bug, idea, other }

SupportCategory supportCategoryOf(String? name) => SupportCategory.values
    .firstWhere((c) => c.name == name, orElse: () => SupportCategory.other);

enum SupportStatus { open, answered, closed }

SupportStatus supportStatusOf(String? name) => SupportStatus.values.firstWhere(
  (s) => s.name == name,
  orElse: () => SupportStatus.open,
);

class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.fromSupport,
    required this.body,
    required this.at,
  });

  final String id;
  final bool fromSupport;
  final String body;
  final DateTime at;

  factory SupportMessage.fromJson(Map<String, dynamic> json) => SupportMessage(
    id: json['id']?.toString() ?? '',
    fromSupport: json['from'] == 'admin',
    body: json['body']?.toString() ?? '',
    at:
        DateTime.tryParse(json['at']?.toString() ?? '')?.toLocal() ??
        DateTime.now(),
  );
}

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.category,
    required this.status,
    required this.unread,
    required this.hasDiagnostics,
    required this.preview,
    required this.lastFromSupport,
    required this.lastMessageAt,
    required this.createdAt,
    this.messages = const [],
  });

  final String id;
  final SupportCategory category;
  final SupportStatus status;

  /// An answer from support this viewer has not opened yet.
  final bool unread;
  final bool hasDiagnostics;
  final String preview;
  final bool lastFromSupport;
  final DateTime lastMessageAt;
  final DateTime createdAt;

  /// Empty in a list; the thread arrives with the ticket itself.
  final List<SupportMessage> messages;

  factory SupportTicket.fromJson(Map<String, dynamic> json) {
    DateTime date(Object? v) =>
        DateTime.tryParse(v?.toString() ?? '')?.toLocal() ?? DateTime.now();
    final raw = json['messages'];
    return SupportTicket(
      id: json['id']?.toString() ?? '',
      category: supportCategoryOf(json['category']?.toString()),
      status: supportStatusOf(json['status']?.toString()),
      unread: json['userUnread'] == true,
      hasDiagnostics: json['hasDiagnostics'] == true,
      preview: json['preview']?.toString() ?? '',
      lastFromSupport: json['lastFrom'] == 'admin',
      lastMessageAt: date(json['lastMessageAt']),
      createdAt: date(json['createdAt']),
      messages: raw is List
          ? raw
                .whereType<Map>()
                .map((m) => SupportMessage.fromJson(m.cast<String, dynamic>()))
                .toList()
          : const [],
    );
  }
}

class SupportInbox {
  const SupportInbox({required this.tickets, required this.unread});

  final List<SupportTicket> tickets;
  final int unread;
}

/// Where a request was started from, so the form opens on the right category
/// and the diagnostics say what was on screen.
class SupportRequestArgs {
  const SupportRequestArgs({
    this.category,
    this.provider,
    this.content,
    this.screen,
  });

  final SupportCategory? category;
  final String? provider;
  final String? content;
  final String? screen;
}

/// A refusal worth showing as it is: the server writes these for people.
class SupportException implements Exception {
  const SupportException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}
