import 'dart:async';

import 'package:dio/dio.dart';
import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/manga/manga_channel.dart';
import 'package:soplay/features/extensions/data/mangayomi_bridge.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/js/js_runtime_service.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/search/data/model/genre_model.dart';
import 'package:soplay/features/search/data/model/search_model.dart';
import 'package:soplay/features/search/domain/repositories/search_repository.dart';
import 'package:soplay/features/search/domain/services/cross_search_engine.dart';

import '../datasources/search_data_source.dart';

class SearchRepositoryImp extends SearchRepository {
  final SearchDataSource dataSource;
  final JsRuntimeService? jsRuntime;
  final HiveService? hive;

  SearchRepositoryImp({
    required this.dataSource,
    required this.mangayomi,
    this.jsRuntime,
    this.hive,
  });

  final MangayomiBridge mangayomi;

  String? get _currentProvider {
    final id = hive?.getCurrentProvider();
    return (id == null || id.isEmpty) ? null : id;
  }

  @override
  Future<Result<List<GenreModel>>> getGenres() async {
    final provider = _currentProvider;
    final catalogue = Catalogue.fromId(provider);
    if (catalogue != null) {
      try {
        return Success(await dataSource.getCatalogueGenres(catalogue.kind));
      } catch (e) {
        return Failure(Exception(e.toString()));
      }
    }
    if (provider != null &&
        (provider.startsWith('cs:') ||
            provider.startsWith('an:') ||
            provider.startsWith('mn:') ||
            provider.startsWith('my:'))) {
      return const Success(<GenreModel>[]);
    }
    try {
      final result = await dataSource.getGenres();
      return Success(result);
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<SearchModel>> getMoviesByGenre(
    String genre, {
    int page = 1,
  }) async {
    try {
      final catalogue = Catalogue.fromId(_currentProvider);
      final result = catalogue != null
          ? await dataSource.getCatalogueGenre(
              catalogue.kind,
              genre,
              page: page,
            )
          : await dataSource.getMoviesByGenre(genre, page: page);
      return Success(result);
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  /// Turns one on-device host's search response into a result.
  ///
  /// The distinction that matters: an **empty map** means the platform channel
  /// itself failed (host missing, PlatformException swallowed in the channel
  /// wrapper) — that is a real failure. A populated map with zero items is a
  /// perfectly good "nothing matched", and used to be reported as
  /// `Exception: Aniyomi: no results`, so a routine empty search rendered the
  /// red error screen instead of the empty state.
  ///
  /// The hosts now also set an `error` field when the source is broken (bad apk,
  /// dex link failure, HTTP error), which lets a genuinely-unusable source stay
  /// distinguishable from one that simply has no match.
  Result<SearchModel> _fromChannel(Map<String, dynamic> map, String label) {
    if (map.isEmpty) return Failure(Exception('$label: source unavailable'));
    final error = (map['error'] as String?)?.trim();
    final model = SearchModel.fromJson(map);
    if (model.items.isEmpty && error != null && error.isNotEmpty) {
      return Failure(Exception('$label: $error'));
    }
    return Success(model);
  }

  /// The budget an on-device host search gets.
  ///
  /// There was none. The backend path goes through Dio, which has connect,
  /// send and receive timeouts; the five host paths below had nothing at all,
  /// so an extension whose `search()` never returns — a dead host, a Cloudflare
  /// challenge page that never resolves, a socket the plugin opened with no
  /// read timeout of its own — left the Search tab spinning forever, with no
  /// error, no empty state and no way out but leaving the screen.
  ///
  /// Borrowed from [CrossSearchEngine.channelTimeout] rather than picked again
  /// here, so the two paths that search the same extension agree about how long
  /// it may take. It is generous for the reason recorded there: the first
  /// search against a freshly-installed source has to download and dex-load its
  /// APK before it can issue a single request.
  static const Duration _hostBudget = CrossSearchEngine.channelTimeout;

  /// Runs one on-device host search under [_hostBudget].
  Future<Result<SearchModel>> _viaHost(
    String label,
    Future<Map<String, dynamic>> Function() search,
  ) async {
    try {
      return _fromChannel(await search().timeout(_hostBudget), label);
    } on TimeoutException {
      // Its own message, and not the channel's: a host that never answered is
      // a different thing from one that answered with a failure, and only this
      // one is worth suggesting another source for.
      return Failure(
        Exception('$label: no answer after ${_hostBudget.inSeconds}s'),
      );
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<SearchModel>> searchMovies(
    String query, {
    int page = 1,
    String? genre,
  }) async {
    final js = jsRuntime;
    final provider = _currentProvider;
    // A catalogue is searched on the backend, in the provider search's shape.
    // Before this, a search with AniList or TMDB as the "source" went to the
    // provider route with an id it had never heard of.
    final catalogue = Catalogue.fromId(provider);
    if (catalogue != null) {
      try {
        return Success(
          await dataSource.searchCatalogue(catalogue.kind, query, page: page),
        );
      } on DioException catch (e) {
        final raw = e.response?.data;
        final message = (raw is Map ? raw['message'] : null) ?? e.message;
        return Failure(Exception(message.toString()));
      } catch (e) {
        return Failure(Exception(e.toString()));
      }
    }
    if (provider != null && provider.startsWith('cs:')) {
      return _viaHost(
        'CloudStream',
        () => CloudStreamChannel.search(provider.substring(3), query, page: page),
      );
    }
    if (provider != null && provider.startsWith('an:')) {
      return _viaHost(
        'Aniyomi',
        () => AniyomiChannel.search(provider.substring(3), query, page: page),
      );
    }
    if (provider != null && provider.startsWith('mn:')) {
      return _viaHost(
        'Manga',
        () => MangaChannel.search(provider.substring(3), query, page: page),
      );
    }
    if (provider != null && provider.startsWith('my:')) {
      return _viaHost(
        'Mangayomi',
        () => mangayomi.search(provider.substring(3), query, page: page),
      );
    }
    if (js != null && provider != null) {
      // The JS runtime falls THROUGH to the backend when it has no answer, so
      // it cannot use _viaHost — but it can still be bounded.
      try {
        final map = await js.trySearch(provider, query, page).timeout(
          _hostBudget,
        );
        if (map != null) return Success(SearchModel.fromJson(map));
      } on TimeoutException {
        return Failure(
          Exception('$provider: no answer after ${_hostBudget.inSeconds}s'),
        );
      } catch (e) {
        return Failure(Exception(e.toString()));
      }
    }
    try {
      final result = await dataSource.searchMovies(query, page: page);
      return Success(result);
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }
}
