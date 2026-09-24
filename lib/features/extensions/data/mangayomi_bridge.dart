import 'package:flutter/foundation.dart';
import 'package:soplay/core/network/http_headers.dart';
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

  String _titleKey(String sourceId, String link) => '$sourceId\u0000$link';

  void _rememberTitle(String sourceId, String link, String title) {
    if (link.isEmpty || title.isEmpty) return;
    if (_titleByLink.length >= _titleCacheMax) {
      // Cheap eviction: drop the oldest insertion. LinkedHashMap preserves
      // insertion order, so the first key is the least recently added.
      _titleByLink.remove(_titleByLink.keys.first);
    }
    _titleByLink[_titleKey(sourceId, link)] = title;
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
    final gh = RegExp(
      r'github(?:usercontent)?\.com/([^/]+)/([^/]+)',
    ).firstMatch(url);
    if (gh != null) return '${gh.group(1)}/${gh.group(2)}';
    return Uri.tryParse(url)?.host ?? 'Mangayomi';
  }

  MangayomiSource? _source(String id) => store.sourceById(id);

  // --- list shapes ---------------------------------------------------------

  /// `{list:[{name,link,imageUrl}], hasNextPage}` → the app's card array.
  /// Why a call produced no cards, told apart from the call failing.
  ///
  /// A source can hand back a shape this app does not read — a bare object, a
  /// list of strings, entries with no link — and every one of those arrives
  /// here as an empty list, indistinguishable from a site that simply had
  /// nothing to say.
  String _emptyReason(String call, dynamic raw) {
    final list = (raw is Map ? raw['list'] : raw);
    if (raw == null) return '$call: returned nothing';
    if (list is! List) return '$call: unexpected shape (${raw.runtimeType})';
    if (list.isEmpty) return '$call: returned an empty list';
    return '$call: ${list.length} entries, none with a link';
  }

  List<Map<String, dynamic>> _cards(dynamic raw, MangayomiSource src) {
    final list = (raw is Map ? raw['list'] : raw);
    if (list is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final e in list) {
      if (e is! Map) continue;
      final link = (e['link'] ?? e['url'])?.toString() ?? '';
      if (link.isEmpty) continue;
      final title = (e['name'] ?? e['title'])?.toString() ?? '';
      _rememberTitle(src.id, link, title);
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
    // What each call actually did, for the case where neither produced rows.
    // "Nothing came back" and "the call blew up" look identical on a blank
    // screen, and a blank screen with no explanation was what a source landing
    // on this path gave people.
    final outcomes = <String>[];
    runtime.dartFetch.clearBlock();

    // Popular and latest are independent calls, but the runtime serialises them
    // anyway (one shared JS context), so issue them in sequence and let one
    // failing call leave the other's results intact.
    try {
      final popular = await runtime.call(id, 'getPopular', args: [page]);
      final items = _cards(popular, src);
      if (items.isEmpty) outcomes.add(_emptyReason('popular', popular));
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
      outcomes.add(
        _isNotImplemented(e) ? 'popular: not implemented' : 'popular: $e',
      );
    }

    try {
      final latest = await runtime.call(id, 'getLatestUpdates', args: [page]);
      final items = _cards(latest, src);
      if (items.isEmpty) outcomes.add(_emptyReason('latest', latest));
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
      outcomes.add(
        _isNotImplemented(e) ? 'latest: not implemented' : 'latest: $e',
      );
    }

    if (sections.isEmpty) {
      error ??= runtime.dartFetch.takeBlock();
      // Last resort, and the important one: two calls that each came back
      // empty used to leave error null, so the home screen rendered a source
      // with no rows, no message and nothing to retry. Whatever happened, say
      // it — "returned nothing" is still an answer.
      error ??= outcomes.isEmpty
          ? 'the source returned nothing'
          : outcomes.join('; ');
    }

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
      return {
        'provider': 'my:$id',
        'items': const [],
        'error': 'source not installed',
      };
    }
    runtime.dartFetch.clearBlock();
    try {
      // Third arg is the filter list; every extension accepts an empty one.
      final raw = await runtime.call(
        id,
        'search',
        args: [query, page, const []],
      );
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

  /// Whether an extension's chapter list already runs oldest-first.
  ///
  /// Upload dates decide when both ends carry one; otherwise the numbers in
  /// the chapter names do. With neither, the upstream convention — newest
  /// first — is assumed, which is what every list was assumed to be before.
  @visibleForTesting
  static bool listedAscending(List<Map> chapters) {
    if (chapters.length < 2) return true;
    final first = chapters.first;
    final last = chapters.last;
    final d1 = int.tryParse(first['dateUpload']?.toString() ?? '');
    final d2 = int.tryParse(last['dateUpload']?.toString() ?? '');
    if (d1 != null && d2 != null && d1 > 0 && d2 > 0 && d1 != d2) {
      return d1 < d2;
    }
    final n1 = _chapterNumberOf(first['name']?.toString() ?? '');
    final n2 = _chapterNumberOf(last['name']?.toString() ?? '');
    if (n1 != null && n2 != null && n1 != n2) return n1 < n2;
    return false;
  }

  /// The chapter number in a name like "Vol.2 Chapter 14.5: Title" — the
  /// number after a chapter/episode word when there is one, else the last
  /// number in the name.
  static double? _chapterNumberOf(String name) {
    final lower = name.toLowerCase();
    final tagged = RegExp(
      r'(?:chapter|chap|ch\.?|episode|ep\.?|глава|серия|bob|qism)\s*(\d+(?:\.\d+)?)',
    ).firstMatch(lower);
    if (tagged != null) return double.tryParse(tagged.group(1)!);
    final all = RegExp(r'\d+(?:\.\d+)?').allMatches(lower).toList();
    return all.isEmpty ? null : double.tryParse(all.last.group(0)!);
  }

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
      // The comment always said "unless"; the code reversed every list, so a
      // source that lists oldest-first came out with chapter 1 last.
      final listed = chapters.whereType<Map>().toList();
      final ordered =
          raw['chapterOrder'] == 'ascending' || listedAscending(listed)
          ? listed
          : listed.reversed.toList();
      for (var i = 0; i < ordered.length; i++) {
        final c = ordered[i];
        final ref = (c['url'] ?? c['link'])?.toString() ?? '';
        if (ref.isEmpty) continue;
        final group = (c['scanlator'] ?? '').toString().trim();
        episodes.add({
          'episode': i + 1,
          'label': (c['name'] ?? 'Chapter ${i + 1}').toString(),
          'mediaRef': ref,
          if (group.isNotEmpty) 'scanlator': group,
        });
      }
    }

    // Extensions commonly omit the name here (see [_titleByLink]); fall back to
    // whatever the card that led here was called, then to the url's last
    // segment so the page is never headed by an empty string.
    final rawName = (raw['name'] ?? raw['title'])?.toString().trim() ?? '';
    final title = rawName.isNotEmpty
        ? rawName
        : (_titleByLink[_titleKey(src.id, url)] ?? _titleFromUrl(url));

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
      // A list, sometimes. bookReadFree returns the chapter as an array of
      // strings, and `toString()` on that produced the literal "[]" — which is
      // not empty, so it passed the has-content check and the reader opened on
      // two square brackets. Joined, and a whitespace-only result is reported
      // as a failure rather than rendered.
      final text = html is List
          ? html.whereType<Object?>().map((e) => '$e').join()
          : (html is String ? html : html?.toString() ?? '');
      return {
        'provider': src.providerId,
        'headers': <String, String>{
          if (src.baseUrl.isNotEmpty) 'Referer': src.baseUrl,
        },
        'pages': const <Map<String, dynamic>>[],
        if (text.trim().isNotEmpty) 'html': text,
        if (text.trim().isEmpty)
          'error': '${src.name}: the chapter came back empty',
      };
    }

    final raw = await runtime.call(id, 'getPageList', args: [chapterUrl]);
    final pages = <Map<String, dynamic>>[];
    final headers = <String, String>{
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
          final page = <String, dynamic>{'index': i, 'imageUrl': u};
          final h = e['headers'];
          if (h is Map && h.isNotEmpty) {
            page['headers'] = <String, String>{
              for (final entry in h.entries)
                entry.key.toString(): entry.value.toString(),
            };
          }
          if (e['cookie'] != null) page['cookie'] = e['cookie'].toString();
          pages.add(page);
        }
      }
    }
    if (pages.isNotEmpty) {
      final custom = await runtime.call(
        id,
        '__sozoImageHeaders',
        args: [pages.map((page) => page['imageUrl']).toList()],
      );
      for (var i = 0; i < pages.length; i++) {
        final own = pages[i]['headers'];
        final providerHeaders = custom is List && i < custom.length
            ? custom[i]
            : null;
        final merged = mergeHttpHeaders([
          <String, String>{
            if (providerHeaders is Map)
              for (final entry in providerHeaders.entries)
                if (entry.value != null)
                  entry.key.toString(): entry.value.toString(),
          },
          <String, String>{
            if (own is Map)
              for (final entry in own.entries)
                entry.key.toString(): entry.value.toString(),
          },
        ]);
        pages[i]['headers'] = await runtime.dartFetch.headersForImage(
          pages[i]['imageUrl'] as String,
          merged,
        );
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
    final subLabels = <String, int>{};

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
        // Blank as well as missing: an empty quality put the source under a
        // nameless server while its parsed HLS rows landed under another.
        final quality = (e['quality'] ?? '').toString().trim();
        final lowerUrl = url.toLowerCase();
        videoSources.add({
          'quality': quality.isEmpty ? 'Source' : quality,
          'videoUrl': url,
          // A type the rest of the app knows. `http` is not one: the download
          // sheet labels hls / mp4 rows as "HLS" / "Direct" and an `http` row
          // got neither, and the player's format hint had nothing to go on.
          //
          // HLS by more than ".m3u8" in the path: masters served as
          // "/playlist" or ".txt" opened as a progressive file and failed.
          'type':
              lowerUrl.contains('m3u8') ||
                  lowerUrl.contains('/hls/') ||
                  RegExp(
                    r'\b(?:hls|m3u8)\b',
                    caseSensitive: false,
                  ).hasMatch(quality)
              ? 'hls'
              : lowerUrl.contains('.mpd')
              ? 'dash'
              : 'mp4',
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
            final lang = (s['label'] ?? s['lang'] ?? '').toString().trim();
            final label = lang.isEmpty ? 'Subtitle' : lang;
            // A second copy of a language, from another video, says which
            // one it belongs to instead of repeating "English".
            final n = subLabels.update(label, (v) => v + 1, ifAbsent: () => 1);
            final own = s['headers'];
            subtitles.add({
              'label': n == 1
                  ? label
                  : '$label · ${quality.isEmpty ? n : quality}',
              'file': file,
              'default': false,
              // The video's Referer and cookies, which hosts check on the
              // subtitle file too; the track's own headers win.
              'headers': {
                ...headers,
                if (own is Map)
                  for (final h in own.entries)
                    h.key.toString(): h.value.toString(),
              },
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
