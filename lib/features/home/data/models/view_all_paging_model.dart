import 'package:soplay/core/js/js_value.dart';
import 'package:soplay/features/home/data/models/movie_model.dart';

import '../../domain/entities/view_all_paging_entity.dart';

class ViewAllPagingModel extends ViewAllPagingEntity {
  ViewAllPagingModel({
    required super.page,
    required super.totalPages,
    required super.provider,
    required super.items,
  });

  factory ViewAllPagingModel.fromJson(Map<String, dynamic> json) {
    return ViewAllPagingModel(
      page: jsonInt(json['page']) ?? 1,
      totalPages: jsonInt(json['totalPages']) ?? 1,
      provider: jsonText(json['provider']) ?? '',
      items: jsonMaps(json['items']).map(MovieModel.fromJson).toList(),
    );
  }
}
