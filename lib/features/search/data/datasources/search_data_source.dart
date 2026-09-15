import 'package:dio/dio.dart';
import 'package:soplay/features/search/data/model/genre_model.dart';

import '../model/search_model.dart';

class SearchDataSource {
  final Dio dio;

  SearchDataSource({required this.dio});

  Future<List<GenreModel>> getGenres() async {
    var response = await dio.get('/contents/genres');
    return (response.data['items'] as List)
        .map((e) => GenreModel.fromJson(e))
        .toList();
  }

  Future<SearchModel> getMoviesByGenre(String genre, {int page = 1}) async {
    var response = await dio.get(
      '/contents/genre/$genre',
      queryParameters: {'page': page},
    );
    return SearchModel.fromJson(response.data);
  }

  Future<SearchModel> getMoviesByCountry(String country, {int page = 1}) async {
    var response = await dio.get(
      '/contents/country/$country',
      queryParameters: {'page': page},
    );
    return SearchModel.fromJson(response.data);
  }

  /// [provider] overrides the interceptor's "current provider", which is what
  /// lets cross-search treat each selected server provider as its own leg
  /// instead of collapsing them into one.
  /// The server's last provider health report: `{checkedAt, sources: {id:
  /// {ok, failedAt, hint}}}`. Empty, not an error, before the first report.
  Future<Map<String, dynamic>> providerHealth() async {
    final response = await dio.get(
      '/contents/providers/health',
      options: Options(extra: const {'skipAuthInterceptor': true}),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// A catalogue's genres, each with an image. Same shape as [getGenres].
  Future<List<GenreModel>> getCatalogueGenres(String kind) async {
    final response = await dio.get('/catalogue/$kind/genres');
    return (response.data['items'] as List)
        .map((e) => GenreModel.fromJson(e))
        .toList();
  }

  /// A page of one of a catalogue's genres. Same shape as [getMoviesByGenre].
  Future<SearchModel> getCatalogueGenre(
    String kind,
    String genre, {
    int page = 1,
  }) async {
    final response = await dio.get(
      '/catalogue/$kind/genre/$genre',
      queryParameters: {'page': page},
    );
    return SearchModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Search inside a catalogue rather than a source. Same shape back.
  Future<SearchModel> searchCatalogue(
    String kind,
    String query, {
    int page = 1,
  }) async {
    final response = await dio.get(
      '/catalogue/$kind/search',
      queryParameters: {'q': query, 'page': page},
    );
    return SearchModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<SearchModel> searchMovies(
    String query, {
    int page = 1,
    String? provider,
  }) async {
    var response = await dio.get(
      '/contents/search',
      queryParameters: {
        'q': query,
        'page': page,
        if (provider != null && provider.isNotEmpty) 'provider': provider,
      },
    );
    return SearchModel.fromJson(response.data);
  }
}
