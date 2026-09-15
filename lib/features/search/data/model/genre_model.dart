import '../../domain/entities/genre_entity.dart';

class GenreModel extends GenreEntity {
  GenreModel({
    required super.provider,
    required super.slug,
    required super.url,
    required super.image,
    super.name,
  });

  factory GenreModel.fromJson(Map<String, dynamic> json) => GenreModel(
    provider: json['provider'] as String? ?? '',
    slug: json['slug'] as String? ?? '',
    url: json['url'] as String? ?? '',
    image: json['image'] as String? ?? '',
    name: json['name'] as String? ?? json['label'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'provider': provider,
    'slug': slug,
    'url': url,
    'image': image,
    'name': name,
  };
}
