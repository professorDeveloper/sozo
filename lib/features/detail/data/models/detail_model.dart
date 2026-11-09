import 'package:soplay/core/js/js_value.dart';
import 'package:soplay/features/detail/domain/entities/detail_entity.dart';
import 'cast_model.dart';
import 'related_model.dart';
import 'screenshot_model.dart';

class DetailModel extends DetailEntity {
  const DetailModel({
    required super.provider,
    required super.contentId,
    required super.contentUrl,
    required super.title,
    required super.description,
    required super.thumbnail,
    required super.year,
    required super.duration,
    required super.country,
    required super.director,
    required super.genres,
    required super.cast,
    required super.likes,
    required super.dislikes,
    required super.isSerial,
    required super.isFavorited,
    required super.screenshots,
    required super.related,
    super.trailerYoutubeId,
  });

  factory DetailModel.fromJson(Map<String, dynamic> json) {
    // Zangetsu sources pass cast and screenshots through as they give them:
    // a screenshot is often a bare url, and a cast member may be a bare name.
    final castList = [
      for (final e in _list(json['cast'])) ?CastModel.tryParse(e),
    ];

    final screenshotList = [
      for (final e in _list(json['screenshots'])) ?ScreenshotModel.tryParse(e),
    ];

    final relatedList = jsonMaps(
      json['related'],
    ).map(RelatedModel.fromJson).toList();

    final genreList = [
      for (final e in _list(json['genres']))
        ?jsonText(e is Map ? e['name'] ?? e['label'] : e),
    ];

    return DetailModel(
      provider: jsonText(json['provider']) ?? '',
      contentId: jsonText(json['contentId']) ?? '',
      contentUrl: jsonText(json['contentUrl']) ?? '',
      title: jsonText(json['title']) ?? '',
      description: json['description'] is String
          ? json['description'] as String
          : '',
      thumbnail: json['thumbnail'] is String
          ? json['thumbnail'] as String
          : null,
      year: jsonInt(json['year']),
      duration: _nonEmpty(json['duration']),
      country: _nonEmpty(json['country']),
      director: _nonEmpty(json['director']),
      genres: genreList,
      cast: castList,
      likes: jsonInt(json['likes']) ?? 0,
      dislikes: jsonInt(json['dislikes']) ?? 0,
      isSerial: _nullableBool(json['isSerial']) ?? false,
      isFavorited: _nullableBool(json['isFavorited']),
      screenshots: screenshotList,
      related: relatedList,
      trailerYoutubeId: _trailerId(json['extra']),
    );
  }

  /// `extra.trailer.youtubeId`, defended at every step.
  ///
  /// `extra` is a free-form bag that differs per provider: most send nothing,
  /// the TMDB-backed ones send a map, and a provider is free to send a string
  /// or a list there tomorrow. A cast that assumes any of it would turn "this
  /// source has no trailer" into a crash on the detail page.
  static String? _trailerId(Object? extra) {
    if (extra is! Map) return null;
    final trailer = extra['trailer'];
    if (trailer is! Map) return null;
    final id = trailer['youtubeId'];
    if (id is! String) return null;
    final trimmed = id.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static bool? _nullableBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
    return null;
  }

  static List<Object?> _list(Object? value) => value is List ? value : const [];

  /// Text only: a number here would be a unit nobody can name.
  static String? _nonEmpty(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }
}
