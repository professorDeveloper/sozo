import 'package:soplay/core/js/js_value.dart';
import 'package:soplay/features/home/data/models/movie_model.dart';

import '../../domain/entities/search_entity.dart';

class SearchModel extends SearchEntity {
  SearchModel({
    required super.provider,
    required super.items,
    required super.page,
    required super.totalPages,
  });

  factory SearchModel.fromJson(Map<String, dynamic> json) {
    return SearchModel(
      page: jsonInt(json['page']) ?? 1,
      totalPages: jsonInt(json['totalPages']) ?? 1,
      provider: jsonText(json['provider']) ?? '',
      items: jsonMaps(json['items']).map(MovieModel.fromJson).toList(),
    );
  }
}
