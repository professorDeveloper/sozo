import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/extensions/source_language.dart' as srclang;
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/extensions/data/mangayomi_repo_store.dart';
import 'package:soplay/features/extensions/data/mangayomi_runtime.dart';
import 'package:soplay/features/extensions/domain/entities/mangayomi_source.dart';

/// Translates between Mangayomi's extension API and the JSON contracts the rest
/// of the app already speaks (the same shapes `MangaHost` / `AniyomiHost` emit).
///
/// Keeping the translation here rather than in each repository means the
/// `my:` provider slots into home / search / detail / reader with the same
/// three-line dispatch the `cs:` / `an:` / `mn:` providers use, and the app
/// never has to know that one of its source kinds happens to be JavaScript.
class MangayomiBridge {
  MangayomiBridge({required this.runtime, required this.store});

  final MangayomiRuntime runtime;
  final MangayomiRepoStore store;

  /// Titles seen in browse/search results, keyed by the entry's link.
  ///
  /// Mangayomi's `getDetail` is only contractually required to fill in the
  /// fields the list view does not already have — cover, description, author,
  /// chapters. A large share of extensions therefore return **no name at all**,
  /// because upstream keeps the one it already stored from the list. Reading it
  /// straight through left most detail pages with a blank title. Remembering
  /// what the card said is the cheapest fix and matches upstream semantics.
  ///
  /// Bounded so a long browsing session can't grow it without limit; entries are
  /// only ever needed between tapping a card and its detail page loading.
  final Map<String, String> _titleByLink = <String, String>{};
  static const int _titleCacheMax = 500;

  void _rememberTitle(String link, String title) {
    if (link.isEmpty || title.isEmpty) return;
    if (_titleByLink.length >= _titleCacheMax) {
      // Cheap eviction: drop the oldest insertion. LinkedHashMap preserves
      // insertion order, so the first key is the least recently added.
      _titleByLink.remove(_titleByLink.keys.first);
    }
    _titleByLink[link] = title;
  }

  static bool get isSupported => MangayomiRuntime.isSupported;

  static String bare(String providerId) =>
      providerId.startsWith('my:') ? providerId.substring(3) : providerId;

  /// Language preference when collapsing same-named sources. Mirrors the
  /// Aniyomi/Manga hosts so all four ecosystems behave identically.
  ///
  /// Reads the user's languages rather than assuming English. The constant
  /// `en → all → rest` this replaced was invisible and total: for a source that
  /// ships one entry per language, the English one held the name and every
  /// other language was dropped from the picker with nothing to say it had
  /// happened. With no languages selected the ordering is byte-for-byte the old
  /// one, so nothing moves for a user who never opens the filter.
  static int _langRank(String lang, List<String> preferred) =>
      srclang.langRank(lang, preferred);

  /// Installed sources in the provider-list shape `ProviderBloc` consumes.
  ///
  /// **Collapsed by name.** Mangayomi indexes publish one entry per language for
  /// the big aggregators — MangaDex ships 45 of them, Comick 41 — all with the
  /// same display name. Listed raw, the provider picker showed "MangaDex" forty-
  /// five times in a row with no way to tell them apart. One entry per name wins
  /// (English first, then `all`), exactly as `AniyomiHost.providersJson` and
  /// `MangaHost.providersJson` already do.
  List<Map<String, dynamic>> listProviders({bool includeNsfw = false}) {
    final preferred = getIt<HiveService>().getProviderLanguages();
    final picked = <String, MangayomiSource>{};
    for (final s in store.sources()) {
      if (s.isNsfw && !includeNsfw) continue;
      // Languages the user asked for do not compete for a name — they are all
      // kept, each under its own key, and the picker labels them apart. Only
      // the languages nobody asked for still collapse, which is what stops
      // MangaDex from filling the list with forty-five identical rows.
      final langPart =
          srclang.langMatches(s.lang, preferred) && preferred.isNotEmpty
              ? '|${srclang.normalizeLang(s.lang)}'
              : '';
      final key = '${s.name.trim().toLowerCase()}|${s.itemType.code}$langPart';
      if (key.startsWith('|')) continue;
      final current = picked[key];
      if (current == null ||
          _langRank(s.lang, preferred) < _langRank(current.lang, preferred)) {
        picked[key] = s;
      }
    }

    final out = <Map<String, dynamic>>[];
    for (final s in picked.values) {
      out.add({
        'id': s.providerId,
        'name': s.name,
        'lang': s.lang,
        'baseUrl': s.baseUrl,
        'icon': s.iconUrl,
        'nsfw': s.isNsfw,
        'repo': _repoLabel(s.repoUrl),
        'mode': 'client',
        'group': 'mangayomi',
        'itemType': s.itemType.code,
      });
    }
    return out;
  }

  static String _repoLabel(String url) {
    final gh = RegExp(r'github(?:usercontent)?\.com/([^/]+)/([^/]+)').firstMatch(url);
    if (gh != null) return '${gh.group(1)}/${gh.group(2)}';
    return Uri.tryParse(url)?.host ?? 'Mangayomi';
  }

  MangayomiSource? _source(String id) => store.sourceById(id);

  // --- list shapes ---------------------------------------------------------

  /// `{list:[{name,link,imageUrl}], hasNextPage}` → the app's card array.
  List<Map<String, dynamic>> _cards(dynamic raw, MangayomiSource src) {
    final list = (raw is Map ? raw['list'] : raw);
    if (list is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final e in list) {
      if (e is! Map) continue;
      final link = (e['link'] ?? e['url'])?.toString() ?? '';
      if (link.isEmpty) continue;
      final title = (e['name'] ?? e['title'])?.toString() ?? '';
      _rememberTitle(link, title);
      out.add({
        'provider': src.providerId,
        'externalId': link,
        'title': title,
        'slug': link,
        'contentUrl': link,
        'thumbnail': (e['imageUrl'] ?? e['cover'])?.toString(),
        'type': switch (src.itemType) {
          MangayomiItemType.anime => 'Anime',
          MangayomiItemType.novel => 'Novel',
          MangayomiItemType.manga => 'Manga',
        },
      });
    }
    return out;
  }

  bool _hasNext(dynamic raw) => raw is Map && raw['hasNextPage'] == true;

  /// True when the extension just doesn't define the method we asked for.
  /// Both our own runtime guard and the upstream convention of throwing
  /// `Error("<name> not implemented")` land here.
  static bool _isNotImplemented(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('not implemented') ||
        s.contains('does not implement') ||
        s.contains('is not a function');
  }

  Future<Map<String, dynamic>> getMainPage(String id, {int page = 1}) async {
    final src = _source(id);
    if (src == null) {
      return {'provider': 'my:$id', 'error': 'source not installed: my:$id'};
    }
    final sections = <Map<String, dynamic>>[];
    final banner = <Map<String, dynamic>>[];
    String? error;
    runtime.dartFetch.clearBlock();

    // Popular and latest are independent calls, but the runtime serialises them
    // anyway (one shared JS context), so issue them in sequence and let one
    // failing call leave the other's results intact.
    try {
      final popular = await runtime.call(id, 'getPopular', args: [page]);
      final items = _cards(popular, src);
      if (items.isNotEmpty) {
        banner.addAll(items.take(12));
        sections.add({
          'key': 'popular',
          'label': 'Popular',
          'viewAll': {'type': 'my', 'slug': 'popular'},
          'items': items,
        });
      }
    } catch (e) {
      // A source that simply doesn't implement getPopular is a real
      // configuration, not a failure — only report it if nothing else works.
      error = _isNotImplemented(e) ? null : 'getPopular: $e';
    }

    try {
      final latest = await runtime.call(id, 'getLatestUpdates', args: [page]);
      final items = _cards(latest, src);
      if (items.isNotEmpty) {
        sections.add({
          'key': 'latest',
          'label': 'Latest',
          'viewAll': {'type': 'my', 'slug': 'latest'},
          'items': items,
        });
      }
    } catch (e) {
      // Plenty of sources don't implement latest at all. Treating that as an
      // error turned a perfectly usable source into a red "home failed" screen.
      if (!_isNotImplemented(e)) error ??= 'getLatestUpdates: $e';
    }

    if (sections.isEmpty) error ??= runtime.dartFetch.takeBlock();

    return {
      'provider': src.providerId,
      'banner': banner,
      'sections': sections,
      if (sections.isEmpty && error != null) 'error': error,
    };
  }

  Future<Map<String, dynamic>> getSection(
    String id,
    String slug, {
    int page = 1,
  }) async {
    final src = _source(id);
    if (src == null) return {'provider': 'my:$id', 'items': const []};
    final raw = await runtime.call(
      id,
      slug == 'latest' ? 'getLatestUpdates' : 'getPopular',
      args: [page],
    );
    return {
      'provider': src.providerId,
      'items': _cards(raw, src),
      'page': page,
      'totalPages': _hasNext(raw) ? page + 1 : page,
    };
  }

  Future<Map<String, dynamic>> search(
    String id,
    String query, {
    int page = 1,
  }) async {
    final src = _source(id);
    if (src == null) {
      return {'provider': 'my:$id', 'items': const [], 'error': 'source not installed'};
    }
    runtime.dartFetch.clearBlock();
    try {
      // Third arg is the filter list; every extension accepts an empty one.
      final raw = await runtime.call(id, 'search', args: [query, page, const []]);
      final items = _cards(raw, src);
      // An extension parses whatever body it gets, so a blocked request comes
      // back as an empty list and not as a throw. Empty because nothing matched
      // and empty because the site never answered are worth telling apart.
      final blocked = items.isEmpty ? runtime.dartFetch.takeBlock() : null;
      return {
        'provider': src.providerId,
        'items': items,
        'query': query,
        'page': page,
        'totalPages': _hasNext(raw) ? page + 1 : page,
        'error': ?blocked,
      };
    } catch (e) {
      return {
        'provider': src.providerId,
        'items': const [],
        'query': query,
        'page': page,
        'totalPages': page,
        'error': '$e',
      };
    }
  }

  // --- detail --------------------------------------------------------------

  Future<Map<String, dynamic>> load(String id, String url) async {
    final src = _source(id);
    if (src == null) return const {};
    final raw = await runtime.call(id, 'getDetail', args: [url]);
    if (raw is! Map) return const {};

    final chapters = raw['episodes'] ?? raw['chapters'];
    final episodes = <Map<String, dynamic>>[];
    if (chapters is List) {
      // Upstream returns newest-first; the app numbers episodes from 1 in
      // reading order, so reverse unless the source already ordered ascending.
      final ordered = chapters.whereType<Map>().toList().reversed.toList();
      for (var i = 0; i < ordered.length; i++) {
        final c = ordered[i];
        final ref = (c['url'] ?? c['link'])?.toString() ?? '';
        if (ref.isEmpty) continue;
        episodes.add({
          'episode': i + 1,
          'label': (c['name'] ?? 'Chapter ${i + 1}').toString(),
          'mediaRef': ref,
        });
      }
    }

    // Extensions commonly omit the name here (see [_titleByLink]); fall back to
    // whatever the card that led here was called, then to the url's last
    // segment so the page is never headed by an empty string.
    final rawName = (raw['name'] ?? raw['title'])?.toString().trim() ?? '';
    final title = rawName.isNotEmpty
        ? rawName
        : (_titleByLink[url] ?? _titleFromUrl(url));

    final isAnime = src.itemType == MangayomiItemType.anime;
    final status = _statusLabel((raw['status'] as num?)?.toInt());
    final description = StringBuffer();
    if (status != null) description.write('• $status');
    final desc = raw['description']?.toString();
    if (desc != null && desc.trim().isNotEmpty) {
      if (description.isNotEmpty) description.write('\n\n');
      description.write(desc.trim());
    }

    return {
      'provider': src.providerId,
      'contentId': url,
      'contentUrl': url,
      'title': title,
      'description': description.toString(),
      'thumbnail': raw['imageUrl']?.toString(),
      'banner': raw['imageUrl']?.toString(),
      'year': null,
      if ((raw['author']?.toString() ?? '').isNotEmpty)
        'director': raw['author'].toString(),
      'genres': (raw['genre'] is List)
          ? (raw['genre'] as List).map((e) => e.toString()).toList()
          : const <String>[],
      'type': switch (src.itemType) {
        MangayomiItemType.anime => 'Anime',
        MangayomiItemType.novel => 'Novel',
        MangayomiItemType.manga => 'Manga',
      },
      'isSerial': isAnime ? episodes.length > 1 : true,
      'cast': const [],
      'related': const [],
      'episodes': episodes,
    };
  }

  /// Last resort title: `/manga/one-piece/` → "One Piece". Ugly beats blank.
  static String _titleFromUrl(String url) {
    final segments = Uri.tryParse(url)?.pathSegments ?? const <String>[];
    final slug = segments.isEmpty
        ? url
        : segments.lastWhere((s) => s.trim().isNotEmpty, orElse: () => url);
    final words = slug
        .replaceAll(RegExp(r'\.(html?|php)$'), '')
        .split(RegExp(r'[-_+%20]+'))
        .where((w) => w.trim().isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1));
    return words.isEmpty ? url : words.join(' ');
  }

  static String? _statusLabel(int? status) => switch (status) {
        0 => 'Ongoing',
        1 => 'Completed',
        2 => 'On hiatus',
        3 => 'Cancelled',
        _ => null,
      };

  // --- manga pages ---------------------------------------------------------

  /// `getPageList(url)` → `[imageUrl]` or `[{url, headers}]`.
  Future<Map<String, dynamic>> pageList(String id, String chapterUrl) async {
    final src = _source(id);
    if (src == null) return const {};

    // A novel chapter is prose, not a list of images, and the extension API
    // says so: novel sources implement `getHtmlContent` and comic sources
    // implement `getPageList`. Calling the wrong one returned nothing, which
    // arrived as an empty reader — the app offered novel sources, labelled them
    // "Novel", and could not open a single chapter of one.
    if (src.itemType == MangayomiItemType.novel) {
      final html = await runtime.call(
        id,
        'getHtmlContent',
        // Both arguments, in the order the extensions declare
        // `getHtmlContent(name, url)`. The name is unused by every source seen
        // so far, but a missing positional argument is a JS TypeError rather
        // than a default.
        args: [src.name, chapterUrl],
      );
      return {
        'provider': src.providerId,
        'headers': <String, String>{
          if (src.baseUrl.isNotEmpty) 'Referer': src.baseUrl,
        },
        'pages': const <Map<String, dynamic>>[],
        'html': html is String ? html : html?.toString(),
      };
    }

    final raw = await runtime.call(id, 'getPageList', args: [chapterUrl]);
    final pages = <Map<String, dynamic>>[];
    Map<String, String> headers = {
      if (src.baseUrl.isNotEmpty) 'Referer': src.baseUrl,
    };
    if (raw is List) {
      for (var i = 0; i < raw.length; i++) {
        final e = raw[i];
        if (e is String) {
          if (e.isEmpty) continue;
          pages.add({'index': i, 'imageUrl': e});
        } else if (e is Map) {
          final u = (e['url'] ?? e['imageUrl'])?.toString() ?? '';
          if (u.isEmpty) continue;
          pages.add({'index': i, 'imageUrl': u});
          final h = e['headers'];
          if (h is Map && h.isNotEmpty) {
            headers = {
              for (final entry in h.entries)
                entry.key.toString(): entry.value.toString(),
            };
          }
        }
      }
    }
    return {'provider': src.providerId, 'headers': headers, 'pages': pages};
  }

  // --- anime videos --------------------------------------------------------

  /// `getVideoList(url)` → `[{url, originalUrl, quality, headers, subtitles}]`.
  Future<Map<String, dynamic>> loadLinks(String id, String episodeUrl) async {
    final src = _source(id);
    if (src == null) return const {};
    final raw = await runtime.call(id, 'getVideoList', args: [episodeUrl]);
    final videoSources = <Map<String, dynamic>>[];
    final subtitles = <Map<String, dynamic>>[];
    final seen = <String>{};
    final seenSub = <String>{};

    if (raw is List) {
      for (final e in raw.whereType<Map>()) {
        final url = (e['url'] ?? e['originalUrl'])?.toString() ?? '';
        if (url.isEmpty || !seen.add(url)) continue;
        final headers = <String, String>{};
        final h = e['headers'];
        if (h is Map) {
          for (final entry in h.entries) {
            headers[entry.key.toString()] = entry.value.toString();
          }
        }
        videoSources.add({
          'quality': (e['quality'] ?? 'Source').toString(),
          'videoUrl': url,
          'type': url.contains('.m3u8') ? 'hls' : 'http',
          'host': src.name,
          'isDefault': videoSources.isEmpty,
          'accessible': true,
          'headers': headers,
        });
        final subs = e['subtitles'];
        if (subs is List) {
          for (final s in subs.whereType<Map>()) {
            final file = (s['file'] ?? s['url'])?.toString() ?? '';
            if (file.isEmpty || !seenSub.add(file)) continue;
            subtitles.add({
              'label': (s['label'] ?? s['lang'] ?? 'Subtitle').toString(),
              'file': file,
              'default': false,
            });
          }
        }
      }
    }

    final first = videoSources.isNotEmpty ? videoSources.first : null;
    return {
      'videoUrl': first?['videoUrl'],
      'type': first?['type'],
      'headers': first?['headers'] ?? const <String, String>{},
      'videoSources': videoSources,
      'subtitles': subtitles,
    };
  }
}
