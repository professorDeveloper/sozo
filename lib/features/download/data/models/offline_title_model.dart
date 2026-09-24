import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/download/domain/entities/offline_title.dart';

abstract final class OfflineTitleModel {
  static Map<String, dynamic> toJson(OfflineTitle t) => {
    'v': 1,
    'contentUrl': t.contentUrl,
    'provider': t.provider,
    if (t.providerName != null) 'providerName': t.providerName,
    'title': t.title,
    if (t.description.isNotEmpty) 'description': t.description,
    if (t.thumbnail != null) 'thumbnail': t.thumbnail,
    if (t.year != null) 'year': t.year,
    if (t.duration != null) 'duration': t.duration,
    if (t.country != null) 'country': t.country,
    if (t.director != null) 'director': t.director,
    if (t.genres.isNotEmpty) 'genres': t.genres,
    'isSerial': t.isSerial,
    if (t.headers.isNotEmpty) 'headers': t.headers,
    'savedAt': t.savedAt,
    // Short keys: a thousand-episode list is written on every refresh.
    'episodes': [
      for (final e in t.episodes)
        {
          'n': e.episode,
          if (e.label.isNotEmpty) 'l': e.label,
          if (e.mediaRef.isNotEmpty) 'r': e.mediaRef,
          if (e.image != null) 'i': e.image,
          if (e.runtime != null) 't': e.runtime,
          if (e.availableLangs.isNotEmpty) 'g': e.availableLangs,
        },
    ],
  };

  static OfflineTitle? fromJson(Map<String, dynamic> json) {
    final contentUrl = _string(json['contentUrl']);
    if (contentUrl.isEmpty) return null;
    return OfflineTitle(
      contentUrl: contentUrl,
      provider: _string(json['provider']),
      providerName: _stringOrNull(json['providerName']),
      title: _string(json['title']),
      description: _string(json['description']),
      thumbnail: _stringOrNull(json['thumbnail']),
      year: (json['year'] as num?)?.toInt(),
      duration: _stringOrNull(json['duration']),
      country: _stringOrNull(json['country']),
      director: _stringOrNull(json['director']),
      genres: _strings(json['genres']),
      isSerial: json['isSerial'] == true,
      headers: _headers(json['headers']),
      savedAt: (json['savedAt'] as num?)?.toInt() ?? 0,
      episodes: [
        for (final raw in (json['episodes'] as List? ?? const []))
          if (raw is Map)
            EpisodeEntity(
              episode: (raw['n'] as num?)?.toInt() ?? 0,
              label: _string(raw['l']),
              mediaRef: _string(raw['r']),
              image: _stringOrNull(raw['i']),
              runtime: _stringOrNull(raw['t']),
              availableLangs: _strings(raw['g']),
            ),
      ],
    );
  }

  static String _string(Object? raw) => raw is String ? raw : '';

  static String? _stringOrNull(Object? raw) =>
      raw is String && raw.isNotEmpty ? raw : null;

  static List<String> _strings(Object? raw) => raw is List
      ? [
          for (final v in raw)
            if (v is String && v.isNotEmpty) v,
        ]
      : const [];

  static Map<String, String> _headers(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries)
        if (e.key is String && e.value != null) e.key as String: '${e.value}',
    };
  }
}
