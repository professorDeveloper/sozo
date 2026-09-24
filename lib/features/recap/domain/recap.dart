import 'package:soplay/features/history/domain/entities/history_item.dart';

/// What to recap: everything strictly before [episode] of one title.
class RecapRequest {
  const RecapRequest({
    required this.provider,
    required this.contentUrl,
    required this.title,
    required this.episode,
    this.label,
    this.season,
    this.tmdbId,
    this.anilistId,
    this.fallbackEpisode,
  });

  final String provider;
  final String contentUrl;

  /// Shown while the server's own title is not known yet.
  final String title;

  /// The episode the viewer is about to start.
  final int episode;

  /// The episode label as the source printed it; the server reads the season
  /// marker out of it.
  final String? label;
  final int? season;
  final int? tmdbId;
  final int? anilistId;

  /// Asked for instead when [episode] has no recap. Set when the viewer
  /// finished an episode and [episode] is the next one, which may not exist
  /// yet or may open a season TMDB has not listed.
  final int? fallbackEpisode;

  /// Progress at which an episode counts as finished, so the one "about to
  /// start" is the next.
  static const double finishedAt = 0.9;

  /// The recap a Continue Watching row points at, or null when there is
  /// nothing before it to recap (a film, a reader row, episode 1).
  static RecapRequest? fromHistory(
    HistoryItem item, {
    int? tmdbId,
    int? anilistId,
  }) {
    if (!item.isSerial || item.mediaType != null) return null;
    if (item.contentUrl.isEmpty) return null;
    final current =
        item.episodeNumber ??
        (item.episodeIndex == null ? null : item.episodeIndex! + 1);
    if (current == null || current < 1) return null;
    final finished = item.progress >= finishedAt;
    final target = finished ? current + 1 : current;
    if (target < 2) return null;
    return RecapRequest(
      provider: item.provider,
      contentUrl: item.contentUrl,
      title: item.title,
      episode: target,
      label: item.episodeLabel,
      tmdbId: tmdbId,
      anilistId: anilistId,
      fallbackEpisode: finished && current >= 2 ? current : null,
    );
  }

  RecapRequest withEpisode(int episode) => RecapRequest(
    provider: provider,
    contentUrl: contentUrl,
    title: title,
    episode: episode,
    label: label,
    season: season,
    tmdbId: tmdbId,
    anilistId: anilistId,
  );
}

class RecapItem {
  const RecapItem({this.season, this.episode, this.name, this.overview = ''});

  /// Null for AniZip's absolute numbering.
  final int? season;

  /// Null when the row stands for a whole earlier season.
  final int? episode;
  final String? name;
  final String overview;

  bool get isSeason => episode == null;

  factory RecapItem.fromJson(Map<String, dynamic> json) => RecapItem(
    season: _int(json['season']),
    episode: _int(json['episode']),
    name: _text(json['name']),
    overview: _text(json['overview']) ?? '',
  );
}

class Recap {
  const Recap({
    required this.text,
    required this.items,
    required this.episode,
    this.title,
    this.season,
    this.upToEpisode,
    this.tmdbId,
    this.anilistId,
    this.attribution,
    this.lang,
    this.fromModel = false,
  });

  final String text;
  final List<RecapItem> items;

  /// The episode the recap stops before.
  final int episode;
  final String? title;
  final int? season;
  final int? upToEpisode;
  final int? tmdbId;
  final int? anilistId;

  /// Whose synopses these are: 'TMDB' or 'AniZip'. Their terms want it shown.
  final String? attribution;
  final String? lang;

  /// Written by the model rather than stitched from the synopses verbatim.
  final bool fromModel;

  /// Paragraphs, with blank lines dropped.
  List<String> get paragraphs => text
      .split(RegExp(r'\n+'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();

  /// Null when the body is not a recap: no text means nothing to show, and
  /// the sheet would rather say "unavailable" than draw an empty page.
  static Recap? fromJson(Object? body, {required int requestedEpisode}) {
    if (body is! Map) return null;
    final json = Map<String, dynamic>.from(body);
    final text = _text(json['text']);
    if (text == null) return null;
    final items = json['items'] is List
        ? (json['items'] as List)
              .whereType<Map>()
              .map((m) => RecapItem.fromJson(Map<String, dynamic>.from(m)))
              .toList()
        : const <RecapItem>[];
    return Recap(
      text: text,
      items: items,
      episode: _int(json['episode']) ?? requestedEpisode,
      title: _text(json['title']),
      season: _int(json['season']),
      upToEpisode: _int(json['upToEpisode']),
      tmdbId: _int(json['tmdbId']),
      anilistId: _int(json['anilistId']),
      attribution: _text(json['attribution']),
      lang: _text(json['lang']),
      fromModel: json['source'] == 'llm',
    );
  }
}

/// No recap exists for this point, and none will on retry: the server found
/// no synopses, or could not place the episode. Never guessed around.
class RecapUnavailable implements Exception {
  const RecapUnavailable();
}

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

String? _text(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}
