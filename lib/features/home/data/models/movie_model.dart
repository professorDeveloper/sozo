import 'package:soplay/core/js/js_value.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';

class MovieModel extends MovieEntity {
  MovieModel({
    required super.externalId,
    required super.title,
    required super.slug,
    required super.url,
    required super.thumbnail,
    super.banner,
    required super.provider,
    required super.year,
    required super.rating,
    required super.qualities,
    required super.category,
    required super.description,
    super.altTitles,
  });

  factory MovieModel.fromJson(Map<String, dynamic> json) {
    return MovieModel(
      externalId: json['externalId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      url: json['contentUrl'] as String? ?? json['url'] as String? ?? '',
      provider: json['provider'] as String? ?? '',
      thumbnail: json['thumbnail'] as String?,
      banner: json['banner'] as String?,
      year: jsonInt(json['year']),
      rating: jsonInt(json['rating']),
      qualities: switch (json['qualities']) {
        final List q => [for (final e in q) ?jsonText(e)],
        _ => null,
      },
      category: json['category'] as String? ?? '',
      altTitles: [
        for (final n in (json['altTitles'] as List?) ?? const [])
          if (n is String && n.trim().isNotEmpty) n.trim(),
      ],
    );
  }
}
