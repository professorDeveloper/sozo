import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import 'package:soplay/features/torrent/data/indexers/nyaa_indexer.dart';
import 'package:soplay/features/torrent/data/indexers/torrent_indexer.dart';
import 'package:soplay/features/torrent/data/info_hash.dart';
import 'package:soplay/features/torrent/data/release_name_parser.dart';
import 'package:soplay/features/torrent/domain/entities/torrent_result.dart';

/// Tokyo Toshokan — an aggregator rather than a tracker of its own.
///
/// It indexes Nyaa and a long tail of smaller sites, which makes it the best
/// second source: it catches releases Nyaa dropped or never carried. The cost
/// is that most of its rows *are* Nyaa rows, so deduplication by info hash is
/// not optional here — see [InfoHash].
///
/// Its RSS is plain RSS 2.0 with no namespace, and everything interesting is
/// packed into an HTML blob inside `<description>`:
///
/// ```html
/// <a href="https://nyaa.si/download/2151070.torrent">Torrent Link</a><br />
/// <a href="magnet:?xt=urn:btih:JASFEDYP3ZEK...">Magnet Link</a><br />
/// <a href="https://www.tokyotosho.info/details.php?id=2105016">Tokyo Tosho</a><br />
/// Size: 843.76MB<br />
/// Authorized: No<br />
/// Submitter: ttsync<br />
/// Comment: Erai release missed by TT
/// ```
///
/// Note what is *not* there: seeder and leecher counts. Tokyo Toshokan does
/// not track swarms, so results come back with null counts and render as
/// [SwarmHealth.unknown] rather than as dead torrents.
class TokyoToshokanIndexer extends TorrentIndexer {
  const TokyoToshokanIndexer(this._dio);

  final Dio _dio;

  @override
  String get id => 'tokyotosho';

  @override
  String get name => 'Tokyo Toshokan';

  @override
  Uri get baseUri => Uri.parse('https://www.tokyotosho.info');

  /// `rss.php` returns one fixed window with no page parameter.
  @override
  bool get supportsPagination => false;

  @override
  Set<TorrentCategory> get categories => const {
        TorrentCategory.all,
        TorrentCategory.anime,
        TorrentCategory.animeEnglish,
        TorrentCategory.animeNonEnglish,
        TorrentCategory.animeRaw,
        TorrentCategory.animeMusicVideo,
        TorrentCategory.liveAction,
      };

  /// Codes read off the live `search.php` form.
  ///
  /// There is no English/non-English split under Anime the way Nyaa has one —
  /// "Anime" is the English-subbed bucket in practice and "Non-English" is a
  /// sibling category, so [TorrentCategory.animeEnglish] maps to plain Anime.
  String? _categoryCode(TorrentCategory category) => switch (category) {
        TorrentCategory.all => null,
        TorrentCategory.anime => '1',
        TorrentCategory.animeEnglish => '1',
        TorrentCategory.animeNonEnglish => '10',
        TorrentCategory.animeRaw => '7',
        TorrentCategory.animeMusicVideo => '9',
        TorrentCategory.liveAction => '8',
      };

  @override
  Future<List<TorrentResult>> search(
    TorrentQuery query, {
    CancelToken? cancelToken,
  }) async {
    // Asking for page 2+ would just repeat page 1.
    if (query.page > 1) return const [];

    final category = _categoryCode(query.category);
    final uri = baseUri.replace(path: '/rss.php', queryParameters: {
      // `terms`, not `search`.
      //
      // An unknown parameter here is ignored rather than rejected, so
      // `search=` returned the site's 150 newest torrents for every query — a
      // search for "frieren" and one for "zzzznonexistentzzz" gave
      // byte-identical results. The name comes from the site's own search form
      // (`<input type="text" name="terms">`). `filter=` for the category is
      // right and was verified separately: `filter=2` returns only Music.
      'terms': query.term,
      'filter': ?category,
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
    } catch (_) {
      return const [];
    }
  }

  static final _magnetHref = RegExp(r'href="(magnet:\?[^"]+)"');
  static final _torrentHref =
      RegExp(r'href="(https?://[^"]+\.torrent[^"]*)"', caseSensitive: false);
  static final _sizeField = RegExp(r'Size:\s*([\d.,]+\s*[KMGT]?i?B)', caseSensitive: false);
  static final _authorized = RegExp(r'Authorized:\s*(\w+)', caseSensitive: false);

  List<TorrentResult> _parseFeed(String body) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(body);
    } on XmlException {
      return const [];
    }

    final out = <TorrentResult>[];
    for (final item in document.findAllElements('item')) {
      final title = _child(item, 'title');
      if (title == null || title.isEmpty) continue;

      // `&` inside the magnet arrives XML-escaped as `&amp;`. innerText
      // already unescapes entities, but CDATA sections do not go through that
      // path, so normalise both.
      final description = (_child(item, 'description') ?? '').replaceAll('&amp;', '&');

      final magnet = _magnetHref.firstMatch(description)?.group(1);
      final torrentUrl = _torrentHref.firstMatch(description)?.group(1) ?? _child(item, 'link');
      if (magnet == null && torrentUrl == null) continue;

      out.add(TorrentResult(
        title: title,
        indexerId: id,
        indexerName: name,
        release: ReleaseNameParser.parse(title),
        // Tokyo Toshokan's magnets carry the Base32 form; normalising here is
        // what lets the repository recognise a Nyaa duplicate.
        infoHash: InfoHash.fromMagnet(magnet),
        magnetUrl: magnet,
        torrentFileUrl: torrentUrl,
        pageUrl: _child(item, 'guid'),
        sizeBytes: NyaaIndexer.parseSize(_sizeField.firstMatch(description)?.group(1)),
        sizeLabel: _sizeField.firstMatch(description)?.group(1),
        categoryLabel: _child(item, 'category'),
        // "Authorized" is Tokyo Toshokan's equivalent of Nyaa's trusted flag:
        // the submitter is the release group itself, not a re-poster.
        trusted:
            (_authorized.firstMatch(description)?.group(1) ?? '').toLowerCase() == 'yes',
      ));
    }
    return out;
  }

  static String? _child(XmlElement item, String localName) {
    for (final child in item.childElements) {
      if (child.localName == localName) {
        final value = child.innerText.trim();
        return value.isEmpty ? null : value;
      }
    }
    return null;
  }
}
