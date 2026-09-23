import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/search/domain/entities/genre_entity.dart';
import 'package:soplay/features/search/domain/entities/search_entity.dart';

abstract class SearchRepository {
  Future<Result<List<GenreEntity>>> getGenres();

  Future<Result<SearchEntity>> getMoviesByGenre(String genre, {int page = 1});

  /// Text search. Genre is NOT a parameter: the server's /contents/search
  /// reads only q, page and provider, so a genre passed here was silently
  /// dropped and the caller got an unfiltered search back. Browsing a genre
  /// goes through [getMoviesByGenre].
  Future<Result<SearchEntity>> searchMovies(String query, {int page = 1});
}

abstract interface class CatalogueSearchRepository {
  String? get catalogueKind;
  Future<Result<List<GenreEntity>>> getDiscoveryGenres(String type);
  Future<Result<SearchEntity>> discover(
    Map<String, String> filters, {
    int page = 1,
  });
}
