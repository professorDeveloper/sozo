import 'package:soplay/features/watch_services/domain/entities/watch_service_entity.dart';

class WatchServiceModel extends WatchServiceEntity {
  const WatchServiceModel({
    required super.id,
    required super.name,
    super.slug,
    super.logo,
    super.priority,
    super.types,
  });

  factory WatchServiceModel.fromJson(Map<String, dynamic> json) =>
      WatchServiceModel(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: (json['name'] as String?)?.trim() ?? '',
        slug: (json['slug'] as String?)?.trim() ?? '',
        logo: _url(json['logo']),
        priority: (json['priority'] as num?)?.toInt() ?? 9999,
        types: [
          for (final t in (json['types'] as List?) ?? const [])
            ?WatchServiceMedia.fromId(t?.toString()),
        ],
      );

  /// Empty is the same as absent here: a blank logo url draws a broken image,
  /// where null draws the service's initials.
  static String? _url(dynamic raw) {
    if (raw is! String) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
