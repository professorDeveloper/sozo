import 'package:soplay/core/js/js_value.dart';
import 'package:soplay/features/home/domain/entities/home_data_entity.dart';

import 'content_filter_model.dart';
import 'home_section_model.dart';
import 'movie_model.dart';

class HomeDataModel extends HomeDataEntity {
  HomeDataModel({
    required super.provider,
    required super.banner,
    required super.sections,
    required super.categories,
    required super.genres,
  });

  factory HomeDataModel.fromJson(
    Map<String, dynamic> json, {
    List<dynamic> categories = const [],
    List<dynamic> genres = const [],
  }) {
    return HomeDataModel(
      provider: json['provider'] as String? ?? '',
      banner: jsonMaps(json['banner']).map(MovieModel.fromJson).toList(),
      sections: jsonMaps(
        json['sections'],
      ).map(HomeSectionModel.fromJson).toList(),
      categories: jsonMaps(
        categories,
      ).map(ContentFilterModel.fromJson).toList(),
      genres: jsonMaps(genres).map(ContentFilterModel.fromJson).toList(),
    );
  }
}
