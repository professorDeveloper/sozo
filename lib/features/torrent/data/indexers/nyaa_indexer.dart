import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import 'package:soplay/features/torrent/data/indexers/torrent_indexer.dart';
import 'package:soplay/features/torrent/data/release_name_parser.dart';
import 'package:soplay/features/torrent/domain/entities/torrent_result.dart';

/// Nyaa and its adult sibling Sukebei.
///
/// Both run the same software and expose the same namespaced RSS feed, so one
/// implementation covers them; only the host and the default category differ.
/// Nyaa is the tracker the anime scene actually uses, and its RSS is the only
/// endpoint here that hands over seeders, info hash, size, category and the
/// trusted flag in one request — no scraping, no second round trip per row.
///
/// Feed shape (verified against the live endpoint):
///
/// ```xml
/// <item>
///   <title>[Salieri] Frieren - Beyond Journey's End S2 - BD (1080p) (HDR) [Dual Audio]</title>
///   <link>https://nyaa.si/download/2150071.torrent</link>
///   <guid isPermaLink="true">https://nyaa.si/view/2150071</guid>
///   <pubDate>Sat, 22 Aug 2026 22:26:33 -0000</pubDate>
///   <nyaa:seeders>50</nyaa:seeders>
///   <nyaa:leechers>11</nyaa:leechers>
///   <nyaa:downloads>266</nyaa:downloads>
///   <nyaa:infoHash>7287ec428ad3c76c565297c54fc8c9d2a397c63f</nyaa:infoHash>
///   <nyaa:categoryId>1_2</nyaa:categoryId>
///   <nyaa:category>Anime - English-translated</nyaa:category>
///   <nyaa:size>1.4 GiB</nyaa:size>
///   <nyaa:trusted>Yes</nyaa:trusted>
///   <nyaa:remake>No</nyaa:remake>
/// </item>
/// ```
///
/// The feed gives an info hash but no magnet, so [TorrentResult.engineLink]
/// builds one and attaches the public tracker list.
class NyaaIndexer extends TorrentIndexer {
  const NyaaIndexer(this._dio, {this.sukebei = false});

  /// The adult instance. Same code path, different host, and gated behind the
  /// app's NSFW preference.
  final bool sukebei;

  final Dio _dio;

  @override
  String get id => sukebei ? 'sukebei' : 'nyaa';

  @override
  String get name => sukebei ? 'Sukebei' : 'Nyaa';

  @override
  Uri get baseUri =>
      Uri.parse(sukebei ? 'https://sukebei.nyaa.si' : 'https://nyaa.si');

  @override
  bool get isNsfw => sukebei;

  @override
  Set<TorrentCategory> get categories => sukebei
      ? const {TorrentCategory.all}
      : const {
          TorrentCategory.all,
          TorrentCategory.anime,
          TorrentCategory.animeEnglish,
          TorrentCategory.animeNonEnglish,
          TorrentCategory.animeRaw,
          TorrentCategory.animeMusicVideo,
          TorrentCategory.liveAction,
        };

  /// Nyaa's category codes, from <https://wotaku.wiki/torrenting/nyaa>.
  ///
  /// Sukebei's tree is unrelated to Nyaa's, so it is never given one — the
  /// unfiltered `0_0` is the only code that means the same thing on both.
  String _categoryCode(TorrentCategory category) {
    if (sukebei) return '0_0';
    return switch (category) {
      TorrentCategory.all => '0_0',
      TorrentCategory.anime => '1_0',
      TorrentCategory.animeMusicVideo => '1_1',
      TorrentCategory.animeEnglish => '1_2',
      TorrentCategory.animeNonEnglish => '1_3',
      TorrentCategory.animeRaw => '1_4',
      TorrentCategory.liveAction => '4_0',
    };
  }

  /// `f=` — 0 no filter, 1 no remakes, 2 trusted only.
  String _filterCode(TorrentFilter filter) => switch (filter) {
        TorrentFilter.none => '0',
        TorrentFilter.noRemakes => '1',
        TorrentFilter.trustedOnly => '2',
      };

  /// `s=` — Nyaa's own sort keys. Always paired with `o=desc`; nobody wants
  /// the least-seeded result first.
  String _sortCode(TorrentSort sort) => switch (sort) {
        TorrentSort.date => 'id',
        TorrentSort.seeders => 'seeders',
        TorrentSort.size => 'size',
        TorrentSort.downloads => 'downloads',
      };

  @override
  Future<List<TorrentResult>> search(
    TorrentQuery query, {
    CancelToken? cancelToken,
  }) async {
    final uri = baseUri.replace(queryParameters: {
      'page': 'rss',
      'q': query.term,
      'c': _categoryCode(query.category),
      'f': _filterCode(query.filter),
      's': _sortCode(query.sort),
      'o': 'desc',
      if (query.page > 1) 'p': '${query.page}',
    });

    try {
      final response = await _dio.getUri<String>(
        uri,
        cancelToken: cancelToken,
        options: Options(responseType: ResponseType.plain),
      );
      final body = response.data;
      if (body == null || body.isEmpty) return const [];
      return _parseFeed(body);
    } on DioException {
      // A dead tracker is routine, not exceptional. The repository merges
      // whatever the other indexers returned.
      return const [];
    } catch (_) {
      return const [];
    }
  }

  List<TorrentResult> _parseFeed(String body) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(body);
    } on XmlException {
      // Nyaa answers rate-limited and maintenance requests with an HTML page
      // under a 200, which is not parseable as XML.
      return const [];
    }

    final out = <TorrentResult>[];
    for (final item in document.findAllElements('item')) {
      final title = _text(item, 'title');
      if (title == null || title.isEmpty) continue;

      final infoHash = _text(item, 'infoHash')?.toLowerCase();
      final torrentUrl = _text(item, 'link');
      // Nothing to hand the engine — skip rather than show an unplayable row.
      if (infoHash == null && torrentUrl == null) continue;

      out.add(TorrentResult(
        title: title,
        indexerId: id,
        indexerName: name,
        release: ReleaseNameParser.parse(title),
        infoHash: infoHash,
        torrentFileUrl: torrentUrl,
        pageUrl: _text(item, 'guid'),
        seeders: _int(item, 'seeders'),
        leechers: _int(item, 'leechers'),
        completed: _int(item, 'downloads'),
        sizeBytes: parseSize(_text(item, 'size')),
        sizeLabel: _text(item, 'size'),
        publishedAt: _parseRfc822(_text(item, 'pubDate')),
        categoryId: _text(item, 'categoryId'),
        categoryLabel: _text(item, 'category'),
        trusted: _yes(item, 'trusted'),
        remake: _yes(item, 'remake'),
      ));
    }
    return out;
  }

  /// Reads a child by local name, ignoring the `nyaa:` prefix.
  ///
  /// Matching on the local name rather than the qualified one is deliberate:
  /// Nyaa and Sukebei declare *different* namespace URIs for the same prefix
  /// (`https://nyaa.si/xmlns/nyaa` vs `https://sukebei.nyaa.si/xmlns/nyaa`),
  /// so anything that keys off the namespace has to special-case the host.
  static String? _text(XmlElement item, String localName) {
    for (final child in item.childElements) {
      if (child.localName == localName) {
        final value = child.innerText.trim();
        return value.isEmpty ? null : value;
      }
    }
    return null;
  }

  /// Null rather than 0 when the element is absent — a missing count is not
  /// the same claim as "nobody is seeding this".
  static int? _int(XmlElement item, String localName) =>
      int.tryParse(_text(item, localName) ?? '');

  static bool _yes(XmlElement item, String localName) =>
      (_text(item, localName) ?? '').toLowerCase() == 'yes';

  /// `1.4 GiB` / `700 MB` / `12.3 KiB` to bytes.
  ///
  /// Nyaa reports binary units (GiB), other trackers report decimal ones (GB),
  /// and a few mix them. The suffix decides the multiplier; a bare number is
  /// read as bytes.
  static int? parseSize(String? raw) {
    if (raw == null) return null;
    final match = RegExp(
      r'([\d.,]+)\s*([KMGT]?)(i?)B',
      caseSensitive: false,
    ).firstMatch(raw);
    if (match == null) return null;

    final value = double.tryParse(match.group(1)!.replaceAll(',', ''));
    if (value == null) return null;

    final base = match.group(3)!.isNotEmpty ? 1024.0 : 1000.0;
    final exponent = switch (match.group(2)!.toUpperCase()) {
      'K' => 1,
      'M' => 2,
      'G' => 3,
      'T' => 4,
      _ => 0,
    };
    var bytes = value;
    for (var i = 0; i < exponent; i++) {
      bytes *= base;
    }
    return bytes.round();
  }

  /// RFC 822 dates, the RSS standard: `Sat, 22 Aug 2026 22:26:33 -0000`.
  ///
  /// Dart's [DateTime.parse] does not accept this shape, and the feed is not
  /// worth a date-formatting dependency for one field.
  static DateTime? _parseRfc822(String? raw) {
    if (raw == null) return null;
    final match = RegExp(
      r'(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})\s*([+-]\d{4}|GMT|UTC)?',
    ).firstMatch(raw);
    if (match == null) return null;

    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    final month = months[match.group(2)!.toLowerCase()];
    if (month == null) return null;

    final utc = DateTime.utc(
      int.parse(match.group(3)!),
      month,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );

    final offset = match.group(7);
    if (offset == null || offset == 'GMT' || offset == 'UTC') return utc;
    final sign = offset.startsWith('-') ? 1 : -1;
    final hours = int.tryParse(offset.substring(1, 3)) ?? 0;
    final minutes = int.tryParse(offset.substring(3, 5)) ?? 0;
    return utc.add(Duration(hours: sign * hours, minutes: sign * minutes));
  }
}
