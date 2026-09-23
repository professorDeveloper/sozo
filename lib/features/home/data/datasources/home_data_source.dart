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

  Future<List<GenreModel>> loadCatalogueGenres(String kind) async {
    final result = await dio.get('/catalogue/$kind/genres');
    return (result.data['items'] as List)
        .map((e) => GenreModel.fromJson(e))
        .toList();
  }

  Future<List<GenreModel>> loadGenres() async {
    final result = await dio.get("/contents/genres");
    return (result.data['items'] as List)
        .map((e) => GenreModel.fromJson(e))
        .toList();
  }

  /// One streaming service's catalogue, paged.
  ///
  /// [slug] is `<serviceId>:<movie|tv>:<REGION>` — the region travels with the
  /// request rather than being read from storage here, so a grid opened for one
  /// country keeps showing that country even if the setting changes while it is
  /// being scrolled.
  Future<ViewAllPagingModel> loadWatchService({
    required String slug,
    required int page,
  }) async {
    final parts = slug.split(':');
    if (parts.length < 3) {
      throw ArgumentError('watch-service slug must be id:type:region');
    }
    final result = await dio.get(
      '/catalogue/tmdb/watch/service/${parts[0]}',
      queryParameters: {'type': parts[1], 'region': parts[2], 'page': page},
    );
    return ViewAllPagingModel.fromJson(result.data);
  }

  /// Catalogue genre tiles share the View All screen with provider sections,
  /// but must never send a cat: identifier to /contents.
  Future<ViewAllPagingModel> loadCatalogueViewAll({
    required String kind,
    required String type,
    required String slug,
    required int page,
  }) async {
    final Response result;
    if (type == 'genre' && slug.isNotEmpty) {
      result = await dio.get(
        '/catalogue/$kind/genre/${Uri.encodeComponent(slug)}',
        queryParameters: {'page': page},
      );
    } else if (type == 'year' && int.tryParse(slug) != null) {
      result = await dio.get(
        '/catalogue/$kind/discover',
        queryParameters: {'year': slug, 'page': page, 'sort': 'popular'},
      );
    } else {
      throw UnsupportedError(
        'This catalogue does not support this collection.',
      );
    }
    return ViewAllPagingModel.fromJson(result.data as Map<String, dynamic>);
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
