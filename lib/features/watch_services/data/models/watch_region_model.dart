import 'package:soplay/features/watch_services/domain/entities/watch_region_entity.dart';

class WatchRegionModel extends WatchRegionEntity {
  const WatchRegionModel({
    required super.code,
    required super.name,
    super.nativeName,
  });

  factory WatchRegionModel.fromJson(Map<String, dynamic> json) {
    final code = (json['code'] as String?)?.trim().toUpperCase() ?? '';
    final name = (json['name'] as String?)?.trim() ?? '';
    return WatchRegionModel(
      code: code,
      // A country with no name is still a country you can pick; showing its
      // code beats dropping it from the list.
      name: name.isEmpty ? code : name,
      nativeName: (json['nativeName'] as String?)?.trim() ?? '',
    );
  }
}
