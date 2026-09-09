import 'package:dio/dio.dart';

import 'package:soplay/features/torrent/data/indexers/torrent_indexer.dart';
import 'package:soplay/features/torrent/data/info_hash.dart';
import 'package:soplay/features/torrent/data/release_name_parser.dart';
import 'package:soplay/features/torrent/domain/entities/release_info.dart';
import 'package:soplay/features/torrent/domain/entities/torrent_result.dart';

/// nekoBT, through its JSON API rather than its rendered page.
///
/// The site is a server-rendered Nuxt app styled with utility classes, so
/// scraping it means anchoring on `href="magnet:"` and reading swarm counts out
/// of the surrounding markup — workable, but it loses the file size and breaks
/// on the next redesign. `GET /api/v1/torrents/search` returns everything the
/// page renders, and several things it does not:
///
/// ```json
/// { "error": false, "data": { "results": [ {
///     "title": "...", "infohash": "a740b68d...", "magnet": "magnet:?...",
///     "filesize": "4541798846", "seeders": "8", "leechers": "5",
///     "completed": "33", "uploaded_at": 1787617813705,
///     "hardsub": false, "batch": false, "audio_lang": "ja", "sub_lang": "",
///     "groups": [ { "display_name": "Arg0", "uploading_group": true } ]
/// } ], "more": true } }
/// ```
///
/// `hardsub`, `batch` and `groups` are stated facts here, not inferences from
/// the file name, so they override what [ReleaseNameParser] guessed. That is
/// the whole reason this indexer is worth having alongside Nyaa: it is the only
/// one of the four that knows whether subtitles are burned in.
class NekoBtIndexer extends TorrentIndexer {
  const NekoBtIndexer(this._dio);

  final Dio _dio;

  /// The API's own page size, echoed back in `data.search.limit`.
  static const _pageSize = 50;

  @override
  String get id => 'nekobt';

  @override
  String get name => 'nekoBT';

  @override
  Uri get baseUri => Uri.parse('https://nekobt.to');

  /// The site is anime-only and its `category` codes do not line up with
  /// Nyaa's tree, so anime queries are served unfiltered rather than wrongly
  /// narrowed.
  @override
  Set<TorrentCategory> get categories => const {
        TorrentCategory.all,
        TorrentCategory.anime,
        TorrentCategory.animeEnglish,
      };

  @override
  Future<List<TorrentResult>> search(
    TorrentQuery query, {
    CancelToken? cancelToken,
  }) async {
    final uri = baseUri.replace(
      path: '/api/v1/torrents/search',
      queryParameters: {
        // `query`, not `q`.
        //
        // The site's own page uses `/search?q=...`, and assuming the API took
        // the same name cost a silent, total failure: an unknown parameter is
        // not rejected, it is ignored, so every search returned the site's
        // default "best" listing. Every query looked like it worked and every
        // result was wrong — Frieren returned Bleach and Hunter x Hunter.
        //
        // The response's own `data.search` object echoes the parameters the
        // server actually understood; that is what settled it. If this ever
        // needs revisiting, check there first.
        'query': query.term,
        'limit': '$_pageSize',
        // `page` is ignored by the API; `offset` is what it actually reads.
        'offset': '${(query.page - 1) * _pageSize}',
      },
    );

    try {
      final response = await _dio.getUri<dynamic>(
        uri,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.json,
          headers: const {'Accept': 'application/json'},
        ),
      );

      final body = response.data;
      if (body is! Map) return const [];
      // The API reports failures in-band with HTTP 200.
      if (body['error'] == true) return const [];

      final results = (body['data'] as Map?)?['results'];
      if (results is! List) return const [];

      return results
          .whereType<Map>()
          .map((row) => _toResult(Map<String, dynamic>.from(row)))
          .whereType<TorrentResult>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  TorrentResult? _toResult(Map<String, dynamic> row) {
    if (row['deleted'] != null || row['hidden'] == true) return null;

    final title = (row['title'] ?? row['auto_title'])?.toString().trim();
    if (title == null || title.isEmpty) return null;

    final magnet = row['magnet']?.toString();
    final hash = InfoHash.normalize(row['infohash']?.toString()) ??
        InfoHash.fromMagnet(magnet);
    if (hash == null && magnet == null) return null;

    final parsed = ReleaseNameParser.parse(title);

    return TorrentResult(
      title: title,
      indexerId: id,
      indexerName: name,
      release: parsed.copyWith(
        group: _primaryGroup(row['groups']),
        // Stated by the tracker; the name-based guess (an .mp4 container
        // implies burned-in subs) is only a heuristic and is wrong often
        // enough to matter. "Not hardsubbed" is only turned into a soft-sub
        // claim when a subtitle language is actually listed — a raw has
        // neither kind, and calling it soft-subbed would put a wrong badge on
        // the row.
        subtitles: _subtitleKind(row),
        // Authoritative in both directions, unlike the title-based guess.
        batch: row['batch'] is bool ? row['batch'] as bool : null,
        // Two audio languages listed means a dual-audio release, whatever the
        // title does or does not say.
        dualAudio: _langCount(row['audio_lang']) > 1 ? true : null,
      ),
      infoHash: hash,
      magnetUrl: magnet,
      pageUrl: row['id'] == null
          ? null
          : baseUri.replace(path: '/torrent/${row['id']}').toString(),
      // Numbers arrive as strings.
      seeders: _int(row['seeders']),
      leechers: _int(row['leechers']),
      completed: _int(row['completed']),
      sizeBytes: _int(row['filesize']),
      publishedAt: _epochMillis(row['uploaded_at']),
      categoryId: row['category']?.toString(),
    );
  }

  /// How subtitles are carried, from the tracker's own fields rather than the
  /// file name. Null when it does not say enough to be sure.
  static SubtitleKind? _subtitleKind(Map<String, dynamic> row) {
    if (row['hardsub'] == true) return SubtitleKind.openCaptions;
    if (row['hardsub'] != false) return null;
    final hasSubs = _langCount(row['sub_lang']) > 0 ||
        _langCount(row['fsub_lang']) > 0;
    return hasSubs ? SubtitleKind.closedCaptions : null;
  }

  /// The group credited with the upload. A torrent can list several — the
  /// encoder, the sub group, the muxer — and `uploading_group` marks the one
  /// the site attributes it to.
  static String? _primaryGroup(Object? groups) {
    if (groups is! List) return null;
    final entries = groups.whereType<Map>();
    if (entries.isEmpty) return null;
    final primary = entries.firstWhere(
      (g) => g['uploading_group'] == true,
      orElse: () => entries.first,
    );
    final name = primary['display_name']?.toString().trim();
    return (name == null || name.isEmpty) ? null : name;
  }

  /// `"ja,en"` -> 2. An empty or absent field counts as zero, not one.
  static int _langCount(Object? raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return 0;
    return value.split(',').where((part) => part.trim().isNotEmpty).length;
  }

  static int? _int(Object? raw) => switch (raw) {
        int value => value,
        num value => value.toInt(),
        String value => int.tryParse(value.trim()),
        _ => null,
      };

  static DateTime? _epochMillis(Object? raw) {
    final millis = _int(raw);
    if (millis == null || millis <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }
}
