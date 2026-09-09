import 'package:soplay/features/extensions/domain/entities/extension_repo_entity.dart';

/// Compiled-in fallback for the "Recommended" lists.
///
/// Used when the backend is unreachable or has no entries for a kind, so the
/// sources pages are never empty on a fresh install with no connectivity. The
/// backend list wins whenever it has anything for that kind — that is the point
/// of moving these server-side.
///
/// The urls here are the *current* ones as of this build. The manga entry
/// points at `index.pb`, which is what Keiyoushi publishes; its `index.min.json`
/// is a two-entry "Outdated App" stub, so the `.json` url resolves to zero
/// installable sources.
///
/// `yuzono/manga-repo` used to be listed here alongside it and is gone.
/// Verified 2026-08-31: its `index.pb` now 404s, its `index.min.json` is the
/// same "Outdated App" / "Update to Mihon 0.20.1+" stub, and its README is
/// Keiyoushi's — the project folded into Keiyoushi, which this list already
/// carries. Recommending it did not fail loudly; it installed the two stub
/// entries, which is why the report was that the wrong thing appeared rather
/// than that nothing did.
///
/// The anime repo is a different story and stays: `yuzono/anime-repo` is alive
/// (253 extensions, apks served from `repo/apk/`, both checked the same day).
class ExtensionRepoDefaults {
  const ExtensionRepoDefaults._();

  static const List<ExtensionRepoEntity> all = [
    // --- CloudStream ------------------------------------------------------
    ExtensionRepoEntity(
      kind: ExtensionRepoKind.cloudstream,
      name: 'Phisher Extensions',
      description: 'Large collection · movies, series & anime',
      url:
          'https://raw.githubusercontent.com/phisher98/cloudstream-extensions-phisher/refs/heads/builds/repo.json',
      order: 0,
    ),
    ExtensionRepoEntity(
      kind: ExtensionRepoKind.cloudstream,
      name: 'Redowan CloudStream',
      description: 'Popular providers · movies & series',
      url:
          'https://raw.githubusercontent.com/redowan99/Redowan-CloudStream/master/repo.json',
      order: 1,
    ),

    // --- Aniyomi (anime) --------------------------------------------------
    ExtensionRepoEntity(
      kind: ExtensionRepoKind.aniyomi,
      name: 'Yuzono Anime',
      description: 'Largest collection · 270+ sources',
      url:
          'https://raw.githubusercontent.com/yuzono/anime-repo/repo/index.min.json',
      badge: '270+',
      order: 0,
    ),
    ExtensionRepoEntity(
      kind: ExtensionRepoKind.aniyomi,
      name: 'Secozzi',
      description: 'Jellyfin · Stremio · Torbox',
      url:
          'https://raw.githubusercontent.com/Secozzi/aniyomi-extensions/repo/index.min.json',
      order: 1,
    ),

    // --- Manga ------------------------------------------------------------
    ExtensionRepoEntity(
      kind: ExtensionRepoKind.manga,
      name: 'Keiyoushi',
      description: 'Manga / manhwa / webtoon · 1300+ extensions',
      url: 'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.pb',
      badge: '1300+',
      order: 0,
    ),

    // --- Mangayomi (JavaScript extensions — work on iOS too) --------------
    ExtensionRepoEntity(
      kind: ExtensionRepoKind.mangayomi,
      name: 'Kodjodevf (official)',
      description: 'Manga & novels · official Mangayomi repo',
      url:
          'https://raw.githubusercontent.com/kodjodevf/mangayomi-extensions/main/index.json',
      novelUrl:
          'https://raw.githubusercontent.com/kodjodevf/mangayomi-extensions/main/novel_index.json',
      order: 0,
    ),
    ExtensionRepoEntity(
      kind: ExtensionRepoKind.mangayomi,
      name: 'm2k3a',
      description: 'Manga · anime · novels',
      url:
          'https://raw.githubusercontent.com/m2k3a/mangayomi-extensions/main/index.json',
      animeUrl:
          'https://raw.githubusercontent.com/m2k3a/mangayomi-extensions/main/anime_index.json',
      novelUrl:
          'https://raw.githubusercontent.com/m2k3a/mangayomi-extensions/main/novel_index.json',
      order: 1,
    ),
    ExtensionRepoEntity(
      kind: ExtensionRepoKind.mangayomi,
      name: 'Swakshan',
      description: 'Anime-focused community sources',
      url:
          'https://raw.githubusercontent.com/Swakshan/mangayomi-swak-extensions/main/index.json',
      animeUrl:
          'https://raw.githubusercontent.com/Swakshan/mangayomi-swak-extensions/main/anime_index.json',
      order: 2,
    ),
    // Small, but every entry counts twice here: the repo is 100% JavaScript
    // (13 anime, 4 manga, all `sourceCodeLanguage: 1`), so nothing in it is
    // skipped on the platforms that cannot run Dart sources. The bigger repos
    // are mostly the other way round — Kodjodevf is 249 Dart to 114 JS and has
    // no anime index at all, and m2k3a's anime index is 40 Dart to 24 JS.
    ExtensionRepoEntity(
      kind: ExtensionRepoKind.mangayomi,
      name: 'Mallyd11',
      description: 'Anime · all-JavaScript, runs on iOS',
      url:
          'https://raw.githubusercontent.com/Mallyd11/mangayomi-anime-extensions/main/index.json',
      animeUrl:
          'https://raw.githubusercontent.com/Mallyd11/mangayomi-anime-extensions/main/anime_index.json',
      order: 3,
    ),
  ];

  static List<ExtensionRepoEntity> forKind(ExtensionRepoKind kind) =>
      all.where((r) => r.kind == kind).toList()
        ..sort((a, b) => a.order.compareTo(b.order));
}
