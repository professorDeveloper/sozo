/// What a Mangayomi source serves. Matches upstream's `itemType` enum.
enum MangayomiItemType {
  manga,
  anime,
  novel;

  static MangayomiItemType fromCode(int? code) => switch (code) {
    1 => MangayomiItemType.anime,
    2 => MangayomiItemType.novel,
    _ => MangayomiItemType.manga,
  };

  int get code => switch (this) {
    MangayomiItemType.manga => 0,
    MangayomiItemType.anime => 1,
    MangayomiItemType.novel => 2,
  };
}

/// One entry from a Mangayomi repository index.
///
/// Mangayomi extensions are **JavaScript**, not Android APKs. That is the whole
/// reason they matter here: CloudStream `.cs3`, Aniyomi and Mihon extensions are
/// all loaded through Android's `DexClassLoader`, which has no iOS equivalent,
/// so those three ecosystems can only ever be Android features. A JS extension
/// runs in the headless WebView the app already ships on every platform, which
/// makes this the route to extension support on iOS.
///
/// `sourceCodeLanguage` matters: `0` = Dart, `1` = JavaScript. Only the
/// JavaScript ones are installable here — the Dart ones are compiled into
/// Mangayomi itself and there is nothing to run.
class MangayomiSource {
  const MangayomiSource({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.lang,
    required this.sourceCodeUrl,
    required this.version,
    required this.itemType,
    this.apiUrl = '',
    this.iconUrl = '',
    this.typeSource = '',
    this.isNsfw = false,
    this.hasCloudflare = false,
    this.isJavaScript = true,
    this.repoUrl = '',
  });

  final String id;
  final String name;
  final String baseUrl;
  final String apiUrl;
  final String lang;
  final String iconUrl;
  final String typeSource;
  final String sourceCodeUrl;
  final String version;
  final MangayomiItemType itemType;
  final bool isNsfw;
  final bool hasCloudflare;
  final bool isJavaScript;

  /// The index this entry came from, so the source can be removed with its repo.
  final String repoUrl;

  /// Provider id used across the app. `my:` keeps it distinct from the Android
  /// hosts (`cs:` / `an:` / `mn:`) so dispatch stays a prefix check.
  String get providerId => 'my:$id';

  /// An LNReader plugin rather than a Mangayomi extension.
  ///
  /// The two are both JavaScript and both end up in the same runtime and the
  /// same registry, so one flag on the source is the whole difference: it picks
  /// which loader compiles the code. Everything after that is the same object
  /// shape — see `assets/js/lnreader.js`.
  ///
  /// Carried on `typeSource`, which is already a free-text field describing
  /// where a source came from, rather than a new column that every stored row
  /// would have to be migrated to grow.
  bool get isLnReader => typeSource == lnReaderType;

  /// The value [isLnReader] looks for.
  static const String lnReaderType = 'lnreader';

  /// Code and constructor inputs must move together when changing repositories.
  String get runtimeIdentity =>
      '$version\u0000$sourceCodeUrl\u0000$repoUrl\u0000'
      '$baseUrl\u0000$apiUrl\u0000$lang\u0000${itemType.code}';

  /// The metadata object handed to the extension as `this.source`. Field names
  /// are upstream's — extensions read `this.source.baseUrl` and friends.
  Map<String, dynamic> toJs() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'apiUrl': apiUrl,
    'lang': lang,
    'typeSource': typeSource,
    'itemType': itemType.code,
    'isNsfw': isNsfw,
    'version': version,
    'iconUrl': iconUrl,
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'apiUrl': apiUrl,
    'lang': lang,
    'iconUrl': iconUrl,
    'typeSource': typeSource,
    'sourceCodeUrl': sourceCodeUrl,
    'version': version,
    'itemType': itemType.code,
    'isNsfw': isNsfw,
    'hasCloudflare': hasCloudflare,
    'isJavaScript': isJavaScript,
    'repoUrl': repoUrl,
  };

  static MangayomiSource? fromIndexJson(
    Map<String, dynamic> json, {
    required String repoUrl,
  }) {
    final id = json['id']?.toString().trim() ?? '';
    final name = (json['name'] as String?)?.trim() ?? '';
    final code = (json['sourceCodeUrl'] as String?)?.trim() ?? '';
    if (id.isEmpty || name.isEmpty || code.isEmpty) return null;
    return MangayomiSource(
      id: id,
      name: name,
      baseUrl: (json['baseUrl'] as String?)?.trim() ?? '',
      apiUrl: (json['apiUrl'] as String?)?.trim() ?? '',
      lang: (json['lang'] as String?)?.trim() ?? 'all',
      iconUrl: (json['iconUrl'] as String?)?.trim() ?? '',
      typeSource: (json['typeSource'] as String?)?.trim() ?? '',
      sourceCodeUrl: code,
      version: (json['version'] as String?)?.trim() ?? '0.0.0',
      itemType: MangayomiItemType.fromCode((json['itemType'] as num?)?.toInt()),
      isNsfw: json['isNsfw'] == true,
      hasCloudflare: json['hasCloudflare'] == true,
      // `sourceCodeLanguage`: 0 = Dart (compiled into Mangayomi, unusable here),
      // 1 = JavaScript. Absent in some older indexes — assume JS and let the
      // load fail loudly rather than silently dropping half a repo.
      isJavaScript: ((json['sourceCodeLanguage'] as num?)?.toInt() ?? 1) == 1,
      repoUrl: repoUrl,
    );
  }

  /// One entry from an LNReader plugin index.
  ///
  /// A different shape for the same idea: a flat array of
  /// `{id, name, site, lang, version, url, iconUrl}`, where `url` is the code
  /// and `site` is the base. Everything else is implied — they are all
  /// JavaScript, they are all novels, and the index has no notion of NSFW or of
  /// a source sitting behind Cloudflare.
  ///
  /// Mapped onto [MangayomiSource] rather than given a type of its own because
  /// the difference between the two ecosystems is entirely in the loader. A
  /// parallel entity would mean a parallel store, a parallel picker and a
  /// parallel path through search — for two fields and a `new Function`.
  ///
  /// The id is prefixed so a plugin cannot collide with a Mangayomi extension
  /// that happens to have picked the same one: they share a registry, and a
  /// collision would silently serve one source's chapters under another's name.
  static MangayomiSource? fromLnReaderJson(
    Map<String, dynamic> json, {
    required String repoUrl,
  }) {
    final id = json['id']?.toString().trim() ?? '';
    final name = (json['name'] as String?)?.trim() ?? '';
    final code = (json['url'] as String?)?.trim() ?? '';
    if (id.isEmpty || name.isEmpty || code.isEmpty) return null;
    return MangayomiSource(
      id: 'ln.$id',
      name: name,
      baseUrl: (json['site'] as String?)?.trim() ?? '',
      lang: (json['lang'] as String?)?.trim() ?? 'all',
      iconUrl: (json['iconUrl'] as String?)?.trim() ?? '',
      typeSource: lnReaderType,
      sourceCodeUrl: code,
      version: (json['version'] as String?)?.trim() ?? '0.0.0',
      itemType: MangayomiItemType.novel,
      repoUrl: repoUrl,
    );
  }

  /// Whether [decoded] is an LNReader index rather than a Mangayomi one.
  ///
  /// Told apart by shape, not by url: an index is an LNReader one when it is a
  /// bare list whose entries carry `url` and `site` and no `sourceCodeUrl`.
  /// Matching on the hostname instead would mean a mirror, a fork or a local
  /// file of the same index could not be added.
  static bool looksLikeLnReaderIndex(Object? decoded) {
    if (decoded is! List || decoded.isEmpty) return false;
    final first = decoded.first;
    if (first is! Map) return false;
    return first['url'] != null &&
        first['site'] != null &&
        first['sourceCodeUrl'] == null;
  }

  static MangayomiSource fromJson(Map<String, dynamic> json) => MangayomiSource(
    id: json['id']?.toString() ?? '',
    name: json['name'] as String? ?? '',
    baseUrl: json['baseUrl'] as String? ?? '',
    apiUrl: json['apiUrl'] as String? ?? '',
    lang: json['lang'] as String? ?? 'all',
    iconUrl: json['iconUrl'] as String? ?? '',
    typeSource: json['typeSource'] as String? ?? '',
    sourceCodeUrl: json['sourceCodeUrl'] as String? ?? '',
    version: json['version'] as String? ?? '0.0.0',
    itemType: MangayomiItemType.fromCode((json['itemType'] as num?)?.toInt()),
    isNsfw: json['isNsfw'] == true,
    hasCloudflare: json['hasCloudflare'] == true,
    isJavaScript: json['isJavaScript'] != false,
    repoUrl: json['repoUrl'] as String? ?? '',
  );
}
