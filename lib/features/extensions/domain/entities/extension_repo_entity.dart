/// Which sources page an [ExtensionRepoEntity] belongs to, and which native host
/// installs it. Mirrors the backend's `ExtensionRepo.kind` enum.
enum ExtensionRepoKind {
  cloudstream,
  aniyomi,
  manga,
  mangayomi,
  zangetsu;

  static ExtensionRepoKind? parse(String? raw) => switch (raw?.trim()) {
        'cloudstream' => ExtensionRepoKind.cloudstream,
        'aniyomi' => ExtensionRepoKind.aniyomi,
        'manga' => ExtensionRepoKind.manga,
        'mangayomi' => ExtensionRepoKind.mangayomi,
        'zangetsu' => ExtensionRepoKind.zangetsu,
        _ => null,
      };

  String get wire => name;
}

/// One entry in a sources page's "Recommended" list.
///
/// These used to be `const` lists compiled into each sources page, which meant a
/// repo going dead — or, as happened with `yuzono/manga-repo`, migrating from
/// `index.min.json` to `index.pb` and deleting the old file — could only be
/// fixed by shipping a new app build. They are served by the backend now and
/// curated from the admin panel; [ExtensionRepoDefaults] keeps a compiled-in
/// copy so the list still renders offline or during a backend outage.
class ExtensionRepoEntity {
  const ExtensionRepoEntity({
    required this.kind,
    required this.name,
    required this.url,
    this.description = '',
    this.animeUrl,
    this.novelUrl,
    this.iconUrl,
    this.badge,
    this.nsfw = false,
    this.order = 0,
  });

  final ExtensionRepoKind kind;
  final String name;
  final String description;

  /// Primary index url. For [ExtensionRepoKind.mangayomi] this is the *manga*
  /// index; [animeUrl] and [novelUrl] carry the siblings when the repo has them.
  final String url;
  final String? animeUrl;
  final String? novelUrl;
  final String? iconUrl;
  final String? badge;
  final bool nsfw;
  final int order;

  /// Every index this entry installs, in install order. One for the APK-based
  /// ecosystems; up to three for Mangayomi.
  List<String> get allUrls => [
        url,
        if (animeUrl != null && animeUrl!.isNotEmpty) animeUrl!,
        if (novelUrl != null && novelUrl!.isNotEmpty) novelUrl!,
      ];
}
