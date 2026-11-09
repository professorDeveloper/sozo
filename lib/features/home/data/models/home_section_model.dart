import 'package:soplay/core/js/js_value.dart';
import 'package:soplay/features/home/data/models/view_all_model.dart';
import 'package:soplay/features/home/domain/entities/home_section_entity.dart';

import 'movie_model.dart';

class HomeSectionModel extends HomeSectionEntity {
  HomeSectionModel({
    required super.key,
    required super.label,
    required super.items,
    required super.viewAll,
  });

  factory HomeSectionModel.fromJson(Map<String, dynamic> json) {
    return HomeSectionModel(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      viewAll: switch (jsonMap(json['viewAll'])) {
        final Map<String, dynamic> v => ViewAllModel.fromJson(v),
        null => ViewAllModel(slug: '', type: ''),
      },
      items: jsonMaps(json['items']).map(MovieModel.fromJson).toList(),
    );
  }
}
