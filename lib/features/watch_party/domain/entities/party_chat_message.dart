/// What a system line in the chat says happened.
enum PartySystemKind { joined, left, host, removed }

/// A chat line broadcast in a watch party. Server payload nests the author
/// under `user: {id, username, photoURL}`. A system line (`type: 'system'`)
/// has a [system] kind and no text; [userId] is who it is about.
class PartyChatMessage {
  final String userId;
  final String? username;
  final String? photoURL;
  final String text;
  final int ts;
  final PartySystemKind? system;

  const PartyChatMessage({
    required this.userId,
    this.username,
    this.photoURL,
    required this.text,
    required this.ts,
    this.system,
  });

  bool get isSystem => system != null;

  static PartySystemKind? _kind(dynamic raw) => switch (raw) {
        'joined' => PartySystemKind.joined,
        'left' => PartySystemKind.left,
        'host' => PartySystemKind.host,
        'removed' => PartySystemKind.removed,
        _ => null,
      };

  /// Null for a system line of a kind this app does not know, so a newer
  /// server cannot put a blank row in an older chat.
  static PartyChatMessage? tryParse(Map<String, dynamic> j) =>
      j['type'] == 'system' && _kind(j['kind']) == null
          ? null
          : PartyChatMessage.fromJson(j);

  /// A `party:state` `chat` array, oldest first.
  static List<PartyChatMessage> listFrom(dynamic raw) {
    if (raw is! List) return const <PartyChatMessage>[];
    return raw
        .whereType<Map>()
        .map((m) => tryParse(Map<String, dynamic>.from(m)))
        .whereType<PartyChatMessage>()
        .toList();
  }

  factory PartyChatMessage.fromJson(Map<String, dynamic> j) {
    final rawUser = j['user'];
    final user = rawUser is Map
        ? Map<String, dynamic>.from(rawUser)
        : const <String, dynamic>{};
    return PartyChatMessage(
      userId: user['id'] as String? ?? '',
      username: user['username'] as String?,
      photoURL: user['photoURL'] as String?,
      text: j['text'] as String? ?? '',
      ts: (j['ts'] as num?)?.toInt() ?? 0,
      system: j['type'] == 'system' ? _kind(j['kind']) : null,
    );
  }
}
