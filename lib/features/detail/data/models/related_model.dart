import 'package:soplay/features/detail/domain/entities/related_entity.dart';

class RelatedModel extends RelatedEntity {
  const RelatedModel({
    required super.provider,
    required super.externalId,
    required super.title,
    required super.description,
    required super.slug,
    required super.contentUrl,
    required super.thumbnail,
    required super.year,
    required super.rating,
    required super.qualities,
    required super.category,
  });

  factory RelatedModel.fromJson(Map<String, dynamic> json) => RelatedModel(
    provider: json['provider'] as String? ?? '',
    externalId: json['externalId'] as String? ?? '',
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    slug: json['slug'] as String? ?? '',
    contentUrl: json['contentUrl'] as String? ?? json['url'] as String? ?? '',
    thumbnail: json['thumbnail'] as String?,
    year: (json['year'] as num?)?.toInt(),
    rating: (json['rating'] as num?)?.toInt() ?? 0,
    qualities: json['qualities'] != null
        ? List<String>.from(json['qualities'] as List)
        : const [],
    category: json['category'] as String? ?? '',
  );
}
