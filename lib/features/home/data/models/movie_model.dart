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
      year: (json['year'] as num?)?.toInt(),
      rating: (json['rating'] as num?)?.toInt(),
      qualities: json['qualities'] != null
          ? List<String>.from(json['qualities'] as List)
          : null,
      category: json['category'] as String? ?? '',
    );
  }
}
