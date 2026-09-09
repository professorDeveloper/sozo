import 'package:soplay/features/extensions/domain/entities/extension_repo_entity.dart';

/// What a source serves. Coarse on purpose — the four ecosystems disagree on
/// the finer distinctions and the catalog only ever groups by these.
enum CatalogItemType {
  anime,
  manga,
  novel,
  video,
  other;

  static CatalogItemType parse(String? raw) => switch (raw?.trim()) {
        'anime' => CatalogItemType.anime,
        'manga' => CatalogItemType.manga,
        'novel' => CatalogItemType.novel,
        'video' => CatalogItemType.video,
        _ => CatalogItemType.other,
      };

  String get wire => name;
}

/// One installable source in the server-harvested catalog.
///
/// The catalog answers the question the sources pages could not: "what is there
/// in my language". Before it, finding French anime meant installing a
/// 300-source repo on the chance that some of it was French — fifteen entries
/// were, and there was no way to know from outside.
///
/// A row is not a thing the app installs directly. [repoUrl] is: the user picks
/// a source, the app adds the repo that carries it through the ecosystem's own
/// host, and the source then appears in the picker like any other.
class CatalogSourceEntity {
  const CatalogSourceEntity({
    required this.id,
    required this.kind,
    required this.name,
    required this.repoUrl,
    this.lang = '',
    this.itemType = CatalogItemType.other,
    this.baseUrl = '',
    this.iconUrl,
    this.version = '',
    this.nsfw = false,
    this.jsRuntime = true,
    this.repoName = '',
    this.verified = false,
  });

  final String id;
  final ExtensionRepoKind kind;
  final String name;
  final String lang;
  final CatalogItemType itemType;
  final String baseUrl;
  final String? iconUrl;
  final String version;
  final bool nsfw;

  /// Mangayomi only, and load-bearing there: `false` means the source is Dart,
  /// which Sozo cannot run — those are compiled into Mangayomi itself. Every
  /// French anime source in the m2k3a repo is one, so offering them would be
  /// offering nothing.
  final bool jsRuntime;

  final String repoUrl;
  final String repoName;

  /// Somebody opened it and something played. Not a rating — a graded promise
  /// about a third-party scraper is one nobody can keep.
  final bool verified;

  /// Whether this app, on this platform, could actually run it.
  ///
  /// The three Kotlin hosts are Android-only; Mangayomi's JavaScript sources run
  /// everywhere, which is the whole reason that ecosystem is supported.
  bool installableOn({required bool android}) {
    if (kind == ExtensionRepoKind.mangayomi) return jsRuntime;
    return android;
  }

  static CatalogSourceEntity? fromJson(Map<String, dynamic> json) {
    final kind = ExtensionRepoKind.parse(json['kind'] as String?);
    final name = (json['name'] as String?)?.trim() ?? '';
    final repoUrl = (json['repoUrl'] as String?)?.trim() ?? '';
    if (kind == null || name.isEmpty || repoUrl.isEmpty) return null;
    return CatalogSourceEntity(
      id: (json['id'] ?? '').toString(),
      kind: kind,
      name: name,
      lang: (json['lang'] as String?)?.trim() ?? '',
      itemType: CatalogItemType.parse(json['itemType'] as String?),
      baseUrl: (json['baseUrl'] as String?)?.trim() ?? '',
      iconUrl: (json['iconUrl'] as String?)?.trim(),
      version: (json['version'] as String?)?.trim() ?? '',
      nsfw: json['nsfw'] == true,
      jsRuntime: json['jsRuntime'] != false,
      repoUrl: repoUrl,
      repoName: (json['repoName'] as String?)?.trim() ?? '',
      verified: json['verified'] == true,
    );
  }
}

/// One row of the catalog's language facet: a code and how many sources carry it.
class CatalogLanguage {
  const CatalogLanguage({
    required this.lang,
    required this.count,
    required this.verified,
  });

  final String lang;
  final int count;
  final int verified;
}
