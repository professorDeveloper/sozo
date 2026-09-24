/// Shapes of the /social API. Parsing is lenient: a missing field becomes a
/// safe default rather than a crash, because an old app keeps talking to a
/// newer server long after either was written.
library;

enum SocialRelation {
  self,
  friends,
  outgoing,
  incoming,
  none;

  static SocialRelation parse(Object? raw) => switch (raw) {
    'self' => self,
    'friends' => friends,
    'outgoing' => outgoing,
    'incoming' => incoming,
    _ => none,
  };
}

enum ProfileVisibility {
  public,
  friends,
  private;

  static ProfileVisibility parse(Object? raw) => switch (raw) {
    'public' => public,
    'private' => private,
    _ => friends,
  };
}

enum RequestPolicy {
  everyone,
  nobody;

  static RequestPolicy parse(Object? raw) =>
      raw == 'nobody' ? nobody : everyone;
}

String? _str(Object? v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

DateTime? _date(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;

Map<String, dynamic> _map(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{};

List<Map<String, dynamic>> _list(Object? v) => v is List
    ? v.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList()
    : const [];

class SocialUser {
  const SocialUser({
    required this.id,
    required this.username,
    this.displayName,
    this.photoURL,
  });

  final String id;
  final String username;
  final String? displayName;
  final String? photoURL;

  String get name => (displayName?.trim().isNotEmpty ?? false)
      ? displayName!.trim()
      : username;

  factory SocialUser.fromJson(Map<String, dynamic> json) => SocialUser(
    id: _str(json['id']) ?? '',
    username: _str(json['username']) ?? '',
    displayName: _str(json['displayName']),
    photoURL: _str(json['photoURL']),
  );
}

class UserSearchResult {
  const UserSearchResult({
    required this.user,
    required this.relation,
    this.requestId,
  });

  final SocialUser user;
  final SocialRelation relation;
  final String? requestId;

  factory UserSearchResult.fromJson(Map<String, dynamic> json) =>
      UserSearchResult(
        user: SocialUser.fromJson(json),
        relation: SocialRelation.parse(json['relation']),
        requestId: _str(json['requestId']),
      );

  UserSearchResult copyWith({
    SocialRelation? relation,
    String? requestId,
    bool clearRequest = false,
  }) => UserSearchResult(
    user: user,
    relation: relation ?? this.relation,
    requestId: clearRequest ? null : requestId ?? this.requestId,
  );
}

class SocialProfile {
  const SocialProfile({
    required this.user,
    required this.relation,
    this.requestId,
    this.friendsCount,
    this.canSeeActivity = false,
    this.acceptsRequests = true,
  });

  final SocialUser user;
  final SocialRelation relation;
  final String? requestId;

  /// Null when the profile hides it from this viewer.
  final int? friendsCount;
  final bool canSeeActivity;
  final bool acceptsRequests;

  factory SocialProfile.fromJson(Map<String, dynamic> json) => SocialProfile(
    user: SocialUser.fromJson(_map(json['user'])),
    relation: SocialRelation.parse(json['relation']),
    requestId: _str(json['requestId']),
    friendsCount: _int(json['friendsCount']),
    canSeeActivity: json['canSeeActivity'] == true,
    acceptsRequests: json['acceptsRequests'] != false,
  );

  SocialProfile copyWith({
    SocialRelation? relation,
    String? requestId,
    bool clearRequest = false,
  }) => SocialProfile(
    user: user,
    relation: relation ?? this.relation,
    requestId: clearRequest ? null : requestId ?? this.requestId,
    friendsCount: friendsCount,
    canSeeActivity: canSeeActivity,
    acceptsRequests: acceptsRequests,
  );
}

class FriendEntry {
  const FriendEntry({required this.user, this.since});

  final SocialUser user;
  final DateTime? since;

  factory FriendEntry.fromJson(Map<String, dynamic> json) => FriendEntry(
    user: SocialUser.fromJson(_map(json['user'])),
    since: _date(json['since']),
  );
}

class FriendRequest {
  const FriendRequest({
    required this.id,
    required this.incoming,
    required this.user,
    this.createdAt,
  });

  final String id;
  final bool incoming;
  final SocialUser user;
  final DateTime? createdAt;

  factory FriendRequest.fromJson(Map<String, dynamic> json) => FriendRequest(
    id: _str(json['id']) ?? '',
    incoming: json['direction'] != 'out',
    user: SocialUser.fromJson(_map(json['user'])),
    createdAt: _date(json['createdAt']),
  );
}

/// The answer to sending, re-sending or accepting a request.
class RequestOutcome {
  const RequestOutcome({required this.relation, this.requestId, this.user});

  final SocialRelation relation;
  final String? requestId;
  final SocialUser? user;

  factory RequestOutcome.fromJson(Map<String, dynamic> json) => RequestOutcome(
    relation: SocialRelation.parse(json['relation']),
    requestId: _str(json['requestId']),
    user: json['user'] is Map ? SocialUser.fromJson(_map(json['user'])) : null,
  );
}

enum ActivityType {
  watched,
  read,
  favorited,
  planned,
  completed,
  unknown;

  static ActivityType parse(Object? raw) => switch (raw) {
    'watched' => watched,
    'read' => read,
    'favorited' => favorited,
    'planned' => planned,
    'completed' => completed,
    _ => unknown,
  };
}

enum ActivityMedia {
  video,
  manga,
  novel;

  static ActivityMedia parse(Object? raw) => switch (raw) {
    'manga' => manga,
    'novel' => novel,
    _ => video,
  };
}

class ActivityItem {
  const ActivityItem({
    required this.id,
    required this.type,
    required this.media,
    required this.provider,
    this.contentUrl,
    this.contentId,
    this.title,
    this.thumbnail,
    this.episodeFrom,
    this.episodeTo,
    this.episodeLabel,
    this.finished = false,
    this.at,
    this.actor,
  });

  final String id;
  final ActivityType type;
  final ActivityMedia media;
  final String provider;
  final String? contentUrl;
  final String? contentId;
  final String? title;
  final String? thumbnail;
  final int? episodeFrom;
  final int? episodeTo;
  final String? episodeLabel;
  final bool finished;
  final DateTime? at;

  /// Set on feed rows; absent on a single user's own list.
  final SocialUser? actor;

  bool get isReading => media != ActivityMedia.video;
  bool get canOpen => contentUrl != null && provider.isNotEmpty;

  factory ActivityItem.fromJson(Map<String, dynamic> json) => ActivityItem(
    id: _str(json['id']) ?? '',
    type: ActivityType.parse(json['type']),
    media: ActivityMedia.parse(json['mediaType']),
    provider: _str(json['provider']) ?? '',
    contentUrl: _str(json['contentUrl']),
    contentId: _str(json['contentId']),
    title: _str(json['title']),
    thumbnail: _str(json['thumbnail']),
    episodeFrom: _int(json['episodeFrom']),
    episodeTo: _int(json['episodeTo']),
    episodeLabel: _str(json['episodeLabel']),
    finished: json['finished'] == true,
    at: _date(json['at']),
    actor: json['actor'] is Map
        ? SocialUser.fromJson(_map(json['actor']))
        : null,
  );
}

class CursorPage<T> {
  const CursorPage(this.items, this.nextCursor);

  final List<T> items;
  final String? nextCursor;

  static CursorPage<T> fromJson<T>(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) parse,
  ) => CursorPage<T>(
    _list(json['items']).map(parse).toList(),
    _str(json['nextCursor']),
  );
}

class SocialSettings {
  const SocialSettings({
    this.visibility = ProfileVisibility.friends,
    this.shareActivity = false,
    this.allowRequests = RequestPolicy.everyone,
  });

  final ProfileVisibility visibility;
  final bool shareActivity;
  final RequestPolicy allowRequests;

  factory SocialSettings.fromJson(Map<String, dynamic> json) => SocialSettings(
    visibility: ProfileVisibility.parse(json['visibility']),
    shareActivity: json['shareActivity'] == true,
    allowRequests: RequestPolicy.parse(json['allowRequests']),
  );

  SocialSettings copyWith({
    ProfileVisibility? visibility,
    bool? shareActivity,
    RequestPolicy? allowRequests,
  }) => SocialSettings(
    visibility: visibility ?? this.visibility,
    shareActivity: shareActivity ?? this.shareActivity,
    allowRequests: allowRequests ?? this.allowRequests,
  );
}

class SocialOverview {
  const SocialOverview({
    this.friends = 0,
    this.incoming = 0,
    this.outgoing = 0,
  });

  final int friends;
  final int incoming;
  final int outgoing;

  static const empty = SocialOverview();

  factory SocialOverview.fromJson(Map<String, dynamic> json) => SocialOverview(
    friends: _int(json['friends']) ?? 0,
    incoming: _int(json['incoming']) ?? 0,
    outgoing: _int(json['outgoing']) ?? 0,
  );
}

/// A failed social call, reduced to what the UI words differently.
class SocialException implements Exception {
  const SocialException(this.kind, {this.message});

  final SocialError kind;

  /// The server's own text; Uzbek, so shown only when nothing better exists.
  final String? message;

  @override
  String toString() =>
      'SocialException($kind${message == null ? '' : ': $message'})';
}

enum SocialError {
  network,
  unauthorized,
  notFound,
  requestsClosed,
  alreadyFriends,
  friendLimit,
  tooManyPending,
  activityHidden,
  rateLimited,
  invalid,
  unknown,
}
