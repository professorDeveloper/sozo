import 'package:soplay/core/js/js_value.dart';
import 'package:soplay/features/detail/domain/entities/cast_entity.dart';

class CastModel extends CastEntity {
  const CastModel({
    required super.id,
    required super.name,
    required super.image,
  });

  factory CastModel.fromJson(Map<String, dynamic> json) => CastModel(
    id: jsonText(json['id']) ?? '',
    name: jsonText(json['name']) ?? '',
    image: jsonText(json['image'] ?? json['avatar'] ?? json['photo']) ?? '',
  );

  /// A cast entry as a map or as a bare name; null for anything else.
  static CastModel? tryParse(Object? raw) {
    final map = jsonMap(raw);
    if (map != null) return CastModel.fromJson(map);
    final name = jsonText(raw);
    return name == null ? null : CastModel(id: '', name: name, image: '');
  }
}
