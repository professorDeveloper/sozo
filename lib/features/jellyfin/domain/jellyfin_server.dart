/// A Jellyfin server the user signed in to, with the session it handed out.
///
/// Keyed by the server's own `ServerId` rather than its address, so history,
/// downloads and My List rows written as `jf:<id>` survive the server moving
/// to a new host or port.
class JellyfinServer {
  const JellyfinServer({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.userId,
    required this.userName,
    required this.accessToken,
    this.version = '',
    this.hiddenLibraries = const [],
    this.addedAt,
  });

  static const String prefix = 'jf:';

  final String id;
  final String name;

  /// Normalised: a scheme, no trailing slash, and any reverse-proxy base path
  /// (`https://host/jellyfin`) kept.
  final String baseUrl;
  final String userId;
  final String userName;
  final String accessToken;
  final String version;

  /// Libraries the user switched off. Stored as the excluded set so a library
  /// created on the server later shows up without a trip to settings.
  final List<String> hiddenLibraries;
  final DateTime? addedAt;

  String get providerId => '$prefix$id';

  String get host => Uri.tryParse(baseUrl)?.authority ?? baseUrl;

  bool shows(String libraryId) => !hiddenLibraries.contains(libraryId);

  JellyfinServer copyWith({
    String? name,
    String? baseUrl,
    String? userId,
    String? userName,
    String? accessToken,
    String? version,
    List<String>? hiddenLibraries,
  }) => JellyfinServer(
    id: id,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    userId: userId ?? this.userId,
    userName: userName ?? this.userName,
    accessToken: accessToken ?? this.accessToken,
    version: version ?? this.version,
    hiddenLibraries: hiddenLibraries ?? this.hiddenLibraries,
    addedAt: addedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'userId': userId,
    'userName': userName,
    'accessToken': accessToken,
    'version': version,
    'hiddenLibraries': hiddenLibraries,
    if (addedAt != null) 'addedAt': addedAt!.millisecondsSinceEpoch,
  };

  static JellyfinServer? fromJson(Object? raw) {
    if (raw is! Map) return null;
    String s(String k) => raw[k]?.toString() ?? '';
    final id = s('id');
    final baseUrl = s('baseUrl');
    final token = s('accessToken');
    if (id.isEmpty || baseUrl.isEmpty || token.isEmpty) return null;
    final added = raw['addedAt'];
    return JellyfinServer(
      id: id,
      name: s('name').isEmpty ? 'Jellyfin' : s('name'),
      baseUrl: baseUrl,
      userId: s('userId'),
      userName: s('userName'),
      accessToken: token,
      version: s('version'),
      hiddenLibraries: [
        for (final e in (raw['hiddenLibraries'] as List?) ?? const [])
          if (e != null) e.toString(),
      ],
      addedAt: added is int ? DateTime.fromMillisecondsSinceEpoch(added) : null,
    );
  }
}
