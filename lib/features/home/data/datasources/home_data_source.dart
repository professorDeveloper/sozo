import 'package:dio/dio.dart';
import 'package:soplay/features/search/data/model/genre_model.dart';

import '../models/home_data_model.dart';
import '../models/view_all_paging_model.dart';

class HomeDataSource {
  final Dio dio;

  const HomeDataSource({required this.dio});

  Future<HomeDataModel> loadHome() async {
    final results = await dio.get('/contents/home');
    return HomeDataModel.fromJson((results).data as Map<String, dynamic>);
  }

  /// A catalogue's home, in the provider home's shape. The backend caches it
  /// and nulls every rail's viewAll, since there is nothing to page into.
  Future<HomeDataModel> loadCatalogueHome(String kind) async {
    final results = await dio.get('/catalogue/$kind/home');
    return HomeDataModel.fromJson(results.data as Map<String, dynamic>);
  }

  Future<List<GenreModel>> loadGenres() async {
    final result = await dio.get("/contents/genres");
    return (result.data['items'] as List)
        .map((e) => GenreModel.fromJson(e))
        .toList();
  }

  Future<ViewAllPagingModel> loadViewAll({
    required String type,
    required String slug,
    required int page,
  }) async {
    final Response result;
    if (slug.isEmpty) {
      result = await dio.get(
        "/contents/$type",
        queryParameters: {"page": page},
      );
    } else {
      result = await dio.get(
        "/contents/$type/$slug",
        queryParameters: {"page": page},
      );
    }

    return ViewAllPagingModel.fromJson((result).data as Map<String, dynamic>);
  }
}
