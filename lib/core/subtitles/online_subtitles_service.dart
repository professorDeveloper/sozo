import 'package:dio/dio.dart';
import 'package:soplay/core/di/injection.dart';

class OnlineSubtitle {
  const OnlineSubtitle({
    required this.url,
    required this.language,
    required this.display,
    this.downloadCount = 0,
    this.hearingImpaired = false,
    this.fileName = '',
    this.format = '',
  });

  final String url;
  final String language;
  final String display;
  final int downloadCount;
  final bool hearingImpaired;
  final String fileName;
  final String format;
}

/// Finds subtitles for a title, through the Sozo backend.
///
/// The search key lives on the server now, not on the device: the backend holds
/// the Wyzie key in its environment and falls back to the free Stremio
/// OpenSubtitles source, so nobody has to paste a key into the app for subtitles
/// to work. Resolving the IMDB id from the title still happens here, because the
/// backend endpoint is keyed by id.
class OnlineSubtitlesService {
  OnlineSubtitlesService._();

  static final Dio _public = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      validateStatus: (s) => s != null && s < 500,
    ),
  );

  static Future<String?> resolveImdbId({
    required String title,
    required bool series,
  }) async {
    final cat = series ? 'series' : 'movie';
    final q = Uri.encodeComponent(title);
    try {
      final res = await _public.get(
        'https://v3-cinemeta.strem.io/catalog/$cat/top/search=$q.json',
      );
      final metas =
          (res.data is Map ? res.data['metas'] : null) as List? ?? const [];
      for (final m in metas) {
        final id = (m is Map ? m['id'] : null)?.toString();
        if (id != null && id.startsWith('tt')) return id;
      }
    } catch (_) {}
    return null;
  }

  static Future<List<OnlineSubtitle>> search({
    required String title,
    bool isSerial = false,
    int? season,
    int? episode,
  }) async {
    final imdb = await resolveImdbId(title: title, series: isSerial);
    if (imdb == null) return const [];

    try {
      final res = await getIt<Dio>().get(
        '/contents/subtitles',
        queryParameters: {
          'id': imdb,
          'type': isSerial ? 'tv' : 'movie',
          // Empty language asks the backend for everything it can find, rather
          // than only English.
          'language': '',
          if (isSerial && season != null) 'season': season,
          if (isSerial && episode != null) 'episode': episode,
        },
      );
      final items =
          (res.data is Map ? res.data['items'] : null) as List? ?? const [];
      final out = <OnlineSubtitle>[];
      for (final m in items) {
        if (m is! Map) continue;
        final url = '${m['file'] ?? m['url'] ?? ''}';
        if (url.isEmpty) continue;
        final lang = '${m['language'] ?? m['lang'] ?? ''}'.toUpperCase();
        out.add(
          OnlineSubtitle(
            url: url,
            language: lang,
            display: '${m['label'] ?? m['display'] ?? lang}',
          ),
        );
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}
