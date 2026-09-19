import 'package:soplay/features/detail/domain/entities/cast_entity.dart';

class CastModel extends CastEntity {
  const CastModel({
    required super.id,
    required super.name,
    required super.image,
  });

  factory CastModel.fromJson(Map<String, dynamic> json) => CastModel(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    image: json['image'] as String? ?? '',
  );
}
