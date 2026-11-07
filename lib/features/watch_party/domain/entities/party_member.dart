/// A single participant in a watch party room.
class PartyMember {
  final String userId;
  final String? username;
  final String? photoURL;
  final String role; // 'host' | 'member'
  final bool online;
  final bool buffering;

  const PartyMember({
    required this.userId,
    this.username,
    this.photoURL,
    this.role = 'member',
    this.online = false,
    this.buffering = false,
  });

  PartyMember copyWith({bool? buffering}) => PartyMember(
        userId: userId,
        username: username,
        photoURL: photoURL,
        role: role,
        online: online,
        buffering: buffering ?? this.buffering,
      );

  bool get isHost => role == 'host';

  factory PartyMember.fromJson(Map<String, dynamic> j) => PartyMember(
        userId: j['userId'] as String? ?? '',
        username: j['username'] as String?,
        photoURL: j['photoURL'] as String?,
        role: j['role'] as String? ?? 'member',
        online: j['online'] as bool? ?? false,
        buffering: j['buffering'] as bool? ?? false,
      );

  /// Defensively parse a `members` array from a socket/REST payload.
  static List<PartyMember> listFrom(dynamic raw) {
    if (raw is! List) return const <PartyMember>[];
    return raw
        .whereType<Map>()
        .map((m) => PartyMember.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }
}
