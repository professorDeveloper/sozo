import 'package:dio/dio.dart';
import 'package:soplay/core/di/injection.dart';

/// Result of asking the backend to translate a subtitle.
class SubtitleTranslationResult {
  const SubtitleTranslationResult({
    required this.url,
    required this.cueCount,
    required this.provider,
    required this.cached,
  });

  /// R2 url of the translated .srt — loaded like any other subtitle track.
  final String url;
  final int cueCount;
  final String provider;

  /// True when it came straight from the cache — meaning it did not count
  /// against the daily limit.
  final bool cached;
}

/// A translation already made for the current media, ready to load.
class ReadySubtitle {
  const ReadySubtitle({
    required this.url,
    required this.targetLang,
    required this.cueCount,
  });
  final String url;
  final String targetLang;
  final int cueCount;
}

/// Today's translation allowance for the account.
class SubtitleQuota {
  const SubtitleQuota({
    required this.enabled,
    required this.limit,
    required this.used,
    required this.remaining,
  });

  final bool enabled;
  final int limit;
  final int used;
  final int remaining;
}

/// Thrown when the account has used up its translations for the day.
class SubtitleDailyLimitReached implements Exception {
  const SubtitleDailyLimitReached(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Asks the backend to translate a subtitle the source has none of in the
/// target language.
///
/// The heavy work — parsing, the provider waterfall, caching — all lives on the
/// server; this just hands over the source url and waits for a translated one.
/// Uses the authenticated Dio because the daily limit is counted per account.
class SubtitleTranslationService {
  const SubtitleTranslationService();

  /// Translations already made for this title/episode, across languages.
  Future<List<ReadySubtitle>> fetchReady({
    required String tmdbId,
    required String type,
    int? season,
    int? episode,
  }) async {
    try {
      final response = await getIt<Dio>().get(
        '/contents/subtitles/ready',
        queryParameters: {
          'tmdbId': tmdbId,
          'type': type,
          'season': ?season,
          'episode': ?episode,
        },
      );
      final items = (response.data is Map ? response.data['items'] : null) as List? ??
          const [];
      return [
        for (final m in items)
          if (m is Map && m['url'] != null)
            ReadySubtitle(
              url: '${m['url']}',
              targetLang: '${m['targetLang'] ?? ''}',
              cueCount: (m['cueCount'] as num?)?.toInt() ?? 0,
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Publishes a finished translation so other viewers can load it directly.
  /// Best-effort — a failure here never blocks playback.
  Future<void> publishReady({
    required String tmdbId,
    required String type,
    int? season,
    int? episode,
    required String targetLang,
    required String srt,
  }) async {
    try {
      await getIt<Dio>().post(
        '/contents/subtitles/ready',
        data: {
          'tmdbId': tmdbId,
          'type': type,
          'season': ?season,
          'episode': ?episode,
          'targetLang': targetLang,
          'srt': srt,
        },
      );
    } catch (_) {}
  }

  /// How many translations the account has left today, for showing before the
  /// person spends one. Returns null if it cannot be read — the UI then simply
  /// omits the count rather than blocking.
  Future<SubtitleQuota?> fetchQuota() async {
    try {
      final response = await getIt<Dio>().get('/contents/subtitles/quota');
      final data = response.data as Map<String, dynamic>;
      return SubtitleQuota(
        enabled: data['enabled'] as bool? ?? false,
        limit: (data['limit'] as num?)?.toInt() ?? 0,
        used: (data['used'] as num?)?.toInt() ?? 0,
        remaining: (data['remaining'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Translates one slice of subtitle lines. Order and count are preserved.
  ///
  /// [count] is true only for the first slice of a file, so the daily limit is
  /// charged once no matter how many slices a movie is split into.
  Future<List<String>> translateLines({
    required List<String> lines,
    required String targetLang,
    required String docKey,
    String? from,
    bool count = false,
  }) async {
    try {
      final response = await getIt<Dio>().post(
        '/contents/subtitles/translate/lines',
        data: {
          'lines': lines,
          'targetLang': targetLang,
          'docKey': docKey,
          'count': count,
          if (from != null && from.isNotEmpty) 'from': from,
        },
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
      final data = response.data as Map<String, dynamic>;
      final out = (data['lines'] as List?)?.map((e) => e.toString()).toList();
      if (out == null || out.length != lines.length) {
        throw Exception('Tarjima natijasi mos kelmadi');
      }
      return out;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final message = _messageFrom(e);
      if (status == 429) throw SubtitleDailyLimitReached(message);
      throw Exception(message);
    }
  }

  Future<SubtitleTranslationResult> translate({
    required String sourceUrl,
    required String targetLang,
    String? from,
    String? title,
    String? tmdbId,
  }) async {
    try {
      final response = await getIt<Dio>().post(
        '/contents/subtitles/translate',
        data: {
          'url': sourceUrl,
          'targetLang': targetLang,
          if (from != null && from.isNotEmpty) 'from': from,
          if (title != null && title.isNotEmpty) 'title': title,
          if (tmdbId != null && tmdbId.isNotEmpty) 'tmdbId': tmdbId,
        },
        options: Options(
          // Translation runs the whole waterfall server-side; the default
          // timeout is far too short for a fresh file.
          receiveTimeout: const Duration(seconds: 90),
        ),
      );
      final data = response.data as Map<String, dynamic>;
      return SubtitleTranslationResult(
        url: data['url'] as String,
        cueCount: (data['cueCount'] as num?)?.toInt() ?? 0,
        provider: data['provider'] as String? ?? '',
        cached: data['cached'] as bool? ?? false,
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final message = _messageFrom(e);
      if (status == 429) throw SubtitleDailyLimitReached(message);
      throw Exception(message);
    }
  }

  String _messageFrom(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
    return e.message ?? 'Tarjima qilib bo\'lmadi';
  }
}
