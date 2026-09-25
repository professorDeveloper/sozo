import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/extractor/extractor_entity.dart';
import 'package:soplay/core/extractor/extractor_runner.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/detail/data/datasources/detail_data_source.dart';
import 'package:soplay/features/detail/data/models/detail_model.dart';
import 'package:soplay/features/detail/data/models/media_resolve_model.dart';
import 'package:soplay/features/detail/data/models/playback_model.dart';
import 'package:soplay/features/detail/domain/entities/detail_entity.dart';
import 'package:soplay/features/detail/domain/entities/media_resolve_entity.dart';
import 'package:soplay/features/detail/domain/entities/playback_entity.dart';
import 'package:soplay/features/home/data/datasources/home_data_source.dart';
import 'package:soplay/features/home/data/models/home_data_model.dart';
import 'package:soplay/features/home/domain/entities/home_data_entity.dart';
import 'package:soplay/features/home/domain/entities/view_all_paging_entity.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/search/data/datasources/search_data_source.dart';
import 'package:soplay/features/search/data/model/search_model.dart';
import 'package:soplay/features/search/domain/entities/genre_entity.dart';
import 'package:soplay/features/search/domain/entities/search_entity.dart';

class ProviderManager {
  final DetailDataSource _detailDataSource;
  final HomeDataSource _homeDataSource;
  final SearchDataSource _searchDataSource;
  final ExtractorRunner _extractor;
  final HiveService _hiveService;
  final List<ProviderEntity> _providers = [];

  ProviderManager({
    required DetailDataSource detailDataSource,
    required HomeDataSource homeDataSource,
    required SearchDataSource searchDataSource,
    required ExtractorRunner extractor,
    required HiveService hiveService,
  }) : _detailDataSource = detailDataSource,
       _homeDataSource = homeDataSource,
       _searchDataSource = searchDataSource,
       _extractor = extractor,
       _hiveService = hiveService;

  void updateProviders(List<ProviderEntity> providers) {
    _providers
      ..clear()
      ..addAll(providers);
  }

  ProviderEntity? getProvider(String id) {
    for (final p in _providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  String get currentProviderId => _hiveService.getCurrentProvider();

  bool _canExtract(ProviderEntity? info) =>
      info != null && info.mode != 'server' && info.extractor != null;

  bool _hasFullScope(ProviderEntity? info) =>
      _canExtract(info) && info!.extractor!.scope == 'all';

  Future<void> _ensureExtractorReady(ProviderEntity provider) async {
    final ref = provider.extractor!;
    await _extractor.loadRuntime();
    await _extractor.loadExtractor(
      ExtractorEntity(
        name: ref.name,
        version: ref.version,
        scope: ref.scope,
        url: ref.url,
      ),
    );
  }

  Future<Result<HomeDataEntity>> getHome({String? providerId}) async {
    final pid = providerId ?? currentProviderId;
    final info = getProvider(pid);
    return _resolve(
      info: info,
      fullScopeRequired: true,
      method: 'getHome',
      args: {},
      fromJson: HomeDataModel.fromJson,
      serverFn: () => _homeDataSource.loadHome(),
    );
  }

  Future<Result<List<GenreEntity>>> getGenres() =>
      _serverCall(() => _homeDataSource.loadGenres());

  Future<Result<ViewAllPagingEntity>> loadViewAll({
    required String key,
    required String slug,
    int page = 1,
  }) => _serverCall(
    () => _homeDataSource.loadViewAll(type: key, slug: slug, page: page),
  );

  Future<Result<SearchEntity>> search({
    String? providerId,
    required String query,
    int page = 1,
  }) async {
    final pid = providerId ?? currentProviderId;
    final info = getProvider(pid);
    return _resolve(
      info: info,
      fullScopeRequired: true,
      method: 'search',
      args: {'query': query, 'page': page},
      fromJson: SearchModel.fromJson,
      serverFn: () => _searchDataSource.searchMovies(query, page: page),
    );
  }

  Future<Result<List<GenreEntity>>> searchGenres() =>
      _serverCall(() => _searchDataSource.getGenres());

  Future<Result<SearchEntity>> getMoviesByGenre(String genre, {int page = 1}) =>
      _serverCall(() => _searchDataSource.getMoviesByGenre(genre, page: page));

  Future<Result<DetailEntity>> getDetail(
    String contentUrl, {
    String? provider,
  }) async {
    final pid = provider ?? currentProviderId;
    final info = getProvider(pid);
    return _resolve(
      info: info,
      fullScopeRequired: true,
      method: 'getDetail',
      args: {'url': contentUrl},
      fromJson: DetailModel.fromJson,
      serverFn: () => _detailDataSource.getDetail(contentUrl, provider: pid),
    );
  }

  Future<Result<PlaybackEntity>> getEpisodes(
    String contentUrl, {
    int page = 1,
    int size = 100,
    String sort = 'asc',
    String? provider,
  }) async {
    final pid = provider ?? currentProviderId;
    final info = getProvider(pid);
    return _resolve(
      info: info,
      fullScopeRequired: true,
      method: 'getEpisodes',
      args: {'url': contentUrl, 'page': page, 'size': size, 'sort': sort},
      fromJson: PlaybackModel.fromJson,
      serverFn: () => _detailDataSource.getEpisodes(
        contentUrl,
        page: page,
        size: size,
        sort: sort,
        provider: pid,
      ),
    );
  }

  Future<Result<MediaResolveEntity>> resolveMedia({
    required String ref,
    required String provider,
    String? lang,
  }) async {
    final info = getProvider(provider);
    return _resolve(
      info: info,
      fullScopeRequired: false,
      method: 'resolveMedia',
      args: {'ref': ref, if (lang != null && lang.isNotEmpty) 'lang': lang},
      fromJson: MediaResolveModel.fromJson,
      serverFn: () => _detailDataSource.resolveMedia(
        ref: ref,
        provider: provider,
        lang: lang,
      ),
    );
  }

  Future<Result<T>> _resolve<T>({
    required ProviderEntity? info,
    required bool fullScopeRequired,
    required String method,
    required Map<String, dynamic> args,
    required T Function(Map<String, dynamic>) fromJson,
    required Future<T> Function() serverFn,
  }) async {
    final useExtractor = fullScopeRequired
        ? _hasFullScope(info)
        : _canExtract(info);

    if (useExtractor) {
      try {
        await _ensureExtractorReady(info!);
        final json = await _extractor.call(info.extractor!.name, method, args);
        return Success(fromJson(json));
      } catch (e) {
        debugPrint(
          '[ProviderManager] extractor $method failed, falling back to server: $e',
        );
      }
    }

    return _serverCall(serverFn);
  }

  Future<Result<T>> _serverCall<T>(Future<T> Function() fn) async {
    try {
      final data = await fn();
      debugPrint('[ProviderManager] _serverCall success: ${data.runtimeType}');
      return Success(data);
    } on DioException catch (e) {
      final raw = e.response?.data;
      final message =
          (raw is Map ? raw['message'] : null) ?? e.message ?? 'Server xatolik';
      debugPrint('[ProviderManager] _serverCall DioError: $message');
      return Failure(Exception(message.toString()));
    } catch (e) {
      debugPrint('[ProviderManager] _serverCall error: $e');
      return Failure(Exception(e.toString()));
    }
  }

  void dispose() {
    _extractor.dispose();
  }
}
