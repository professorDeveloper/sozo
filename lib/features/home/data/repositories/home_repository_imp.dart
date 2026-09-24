import 'package:dio/dio.dart';
import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/manga/manga_channel.dart';
import 'package:soplay/features/extensions/data/mangayomi_bridge.dart';
import 'package:soplay/features/jellyfin/data/jellyfin_bridge.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/js/js_runtime_service.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/home/data/datasources/home_data_source.dart';
import 'package:soplay/features/home/data/models/home_data_model.dart';
import 'package:soplay/features/home/data/models/view_all_paging_model.dart';
import 'package:soplay/features/home/domain/entities/view_all_paging_entity.dart';
import 'package:soplay/features/home/domain/repositories/home_repository.dart';
import 'package:soplay/features/search/domain/entities/genre_entity.dart';
import 'package:soplay/features/search/data/model/genre_model.dart';

import '../../domain/entities/home_data_entity.dart';

class HomeRepositoryImp implements HomeRepository {
  final HomeDataSource dataSource;
  final JsRuntimeService? jsRuntime;
  final HiveService? hive;

  const HomeRepositoryImp(
    this.dataSource, {
    required this.mangayomi,
    this.jellyfin,
    this.jsRuntime,
    this.hive,
    this.onOutcome,
  });

  /// Told how each home load went, for the source health record: opening a
  /// source's home is the same evidence a check would gather, for free.
  final void Function(String providerId, bool ok, String? error)? onOutcome;

  final MangayomiBridge mangayomi;
  final JellyfinBridge? jellyfin;

  String? get _currentProvider {
    final id = hive?.getCurrentProvider();
    return (id == null || id.isEmpty) ? null : id;
  }

  /// Runs one on-device host's `getMainPage` and maps it to a [Result].
  ///
  /// An empty map means the platform channel itself failed; a populated map
  /// with an `error` field means the host ran but the source is broken. Both
  /// are failures, but only the second one can say something useful.
  Future<Result<HomeDataEntity>> _fromHost(
    Future<Map<String, dynamic>> Function() call,
    String label,
  ) async {
    try {
      final map = await call();
      if (map.isEmpty) return Failure(Exception('$label: source unavailable'));
      final err = map['error'];
      if (err is String && err.isNotEmpty) {
        return Failure(Exception('$label: $err'));
      }
      return Success(HomeDataModel.fromJson(map));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<HomeDataEntity>> loadHome() async {
    final provider = _currentProvider;
    final result = await _loadHome();
    final report = onOutcome;
    if (report != null && provider != null && !Catalogue.isId(provider)) {
      switch (result) {
        case Success(:final value):
          final items =
              value.banner.length +
              value.sections.fold<int>(0, (n, s) => n + s.items.length);
          if (items > 0) report(provider, true, null);
        case Failure(:final error):
          report(provider, false, error.toString());
      }
    }
    return result;
  }

  Future<Result<HomeDataEntity>> _loadHome() async {
    final js = jsRuntime;
    final provider = _currentProvider;
    // Every on-device host reports *why* it came back empty in an `error` field
    // (bad apk, dex link failure, HTTP status from the source). Surfacing that
    // instead of a flat "home not found" is the difference between a user who
    // can act — re-add the repo, update the extension — and one who just sees a
    // blank screen. None of these paths touch our backend, so they must keep
    // working during an outage.
    // A catalogue before any host: it is the one "provider" that no host
    // serves and the backend does, and asking a host for `cat:anilist` would
    // get an honest-looking "source not installed".
    final catalogue = Catalogue.fromId(provider);
    if (catalogue != null) {
      try {
        return Success(await dataSource.loadCatalogueHome(catalogue.kind));
      } on DioException catch (e) {
        final raw = e.response?.data;
        final message = (raw is Map ? raw['message'] : null) ?? e.message;
        return Failure(Exception(message.toString()));
      } catch (e) {
        return Failure(Exception(e.toString()));
      }
    }
    if (provider != null && provider.startsWith('cs:')) {
      return _fromHost(
        () => CloudStreamChannel.getMainPage(provider.substring(3)),
        'CloudStream',
      );
    }
    if (provider != null && provider.startsWith('an:')) {
      return _fromHost(
        () => AniyomiChannel.getMainPage(provider.substring(3)),
        'Aniyomi',
      );
    }
    if (provider != null && provider.startsWith('mn:')) {
      return _fromHost(
        () => MangaChannel.getMainPage(provider.substring(3)),
        'Manga',
      );
    }
    if (provider != null && provider.startsWith('my:')) {
      return _fromHost(
        () => mangayomi.getMainPage(provider.substring(3)),
        'Mangayomi',
      );
    }
    final jf = jellyfin;
    if (jf != null && provider != null && provider.startsWith('jf:')) {
      return _fromHost(
        () => jf.getMainPage(JellyfinBridge.bare(provider)),
        'Jellyfin',
      );
    }
    if (js != null && provider != null) {
      try {
        final map = await js.tryGetHome(provider);
        if (map != null) return Success(HomeDataModel.fromJson(map));
      } catch (e) {
        return Failure(Exception(e.toString()));
      }
    }

    try {
      final data = await dataSource.loadHome();
      return Success(data);
    } on DioException catch (e) {
      final raw = e.response?.data;
      final message =
          (raw is Map ? raw['message'] : null) ??
          e.message ??
          'Xatolik yuz berdi';
      return Failure(Exception(message.toString()));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<ViewAllPagingEntity>> loadViewAll({
    required String key,
    required String slug,
    int page = 1,
  }) async {
    final js = jsRuntime;
    final provider = _currentProvider;
    // A streaming service is not any source's section — it is TMDB's answer
    // about a country, asked the same way whichever source happens to be
    // current. Ahead of the prefix branches for that reason: the active source
    // is irrelevant here, and letting a CloudStream extension be asked for a
    // Netflix page would be nonsense.
    if (key == 'catalogue-discover') {
      final parts = slug.split(':');
      if (parts.length != 2 ||
          !{
            'anilist',
            'anilist-manga',
            'anilist-novel',
          }.contains(parts.first)) {
        return Failure(Exception('Invalid catalogue collection'));
      }
      try {
        return Success(
          await dataSource.loadCatalogueViewAll(
            kind: parts.first,
            type: 'discover',
            slug: parts.last,
            page: page,
          ),
        );
      } catch (e) {
        return Failure(Exception(e.toString()));
      }
    }
    if (key == 'watch-service') {
      try {
        return Success(
          await dataSource.loadWatchService(slug: slug, page: page),
        );
      } on DioException catch (e) {
        final raw = e.response?.data;
        final message = (raw is Map ? raw['message'] : null) ?? e.message;
        return Failure(Exception(message.toString()));
      } catch (e) {
        return Failure(Exception(e.toString()));
      }
    }
    final catalogue = Catalogue.fromId(provider);
    if (catalogue != null) {
      try {
        return Success(
          await dataSource.loadCatalogueViewAll(
            kind: catalogue.kind,
            type: key,
            slug: slug,
            page: page,
          ),
        );
      } catch (e) {
        return Failure(Exception(e.toString()));
      }
    }
    if (provider != null && provider.startsWith('cs:')) {
      try {
        final map = await CloudStreamChannel.getSection(
          provider.substring(3),
          slug,
          page: page,
        );
        return Success(ViewAllPagingModel.fromJson(map));
      } catch (e) {
        return Failure(Exception(e.toString()));
      }
    }
    if (provider != null && provider.startsWith('an:')) {
      try {
        final map = await AniyomiChannel.getSection(
          provider.substring(3),
          slug,
          page: page,
        );
        return Success(ViewAllPagingModel.fromJson(map));
      } catch (e) {
        return Failure(Exception(e.toString()));
      }
    }
    if (provider != null && provider.startsWith('mn:')) {
      try {
        final map = await MangaChannel.getSection(
          provider.substring(3),
          slug,
          page: page,
        );
        return Success(ViewAllPagingModel.fromJson(map));
      } catch (e) {
        return Failure(Exception(e.toString()));
      }
    }
    if (provider != null && provider.startsWith('my:')) {
      try {
        final map = await mangayomi.getSection(
          provider.substring(3),
          slug,
          page: page,
        );
        return Success(ViewAllPagingModel.fromJson(map));
      } catch (e) {
        return Failure(Exception(e.toString()));
      }
    }
    final jf = jellyfin;
    if (jf != null && provider != null && provider.startsWith('jf:')) {
      try {
        // Home's genre tiles open a view-all keyed `genre` with the bare id.
        final map = await jf.getSection(
          JellyfinBridge.bare(provider),
          key == 'genre' ? 'genre:$slug' : slug,
          page: page,
        );
        return Success(ViewAllPagingModel.fromJson(map));
      } catch (e) {
        return Failure(Exception(jf.describe(e)));
      }
    }
    if (js != null && provider != null && key == 'category') {
      try {
        final map = await js.tryGetCategory(provider, slug, page);
        if (map != null) return Success(ViewAllPagingModel.fromJson(map));
      } catch (e) {
        return Failure(Exception(e.toString()));
      }
    }

    try {
      final data = await dataSource.loadViewAll(
        slug: slug,
        page: page,
        type: key,
      );
      return Success(data);
    } on DioException catch (e) {
      final raw = e.response?.data;
      final message =
          (raw is Map ? raw['message'] : null) ??
          e.message ??
          'Xatolik yuz berdi';
      return Failure(Exception(message.toString()));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<List<GenreEntity>>> loadGenres() async {
    final provider = _currentProvider;
    final catalogue = Catalogue.fromId(provider);
    if (catalogue != null) {
      try {
        return Success(await dataSource.loadCatalogueGenres(catalogue.kind));
      } catch (_) {
        return const Success(<GenreEntity>[]);
      }
    }
    if (provider != null && provider.startsWith('cs:')) {
      try {
        final list = await CloudStreamChannel.getGenres(provider.substring(3));
        final genres = list
            .whereType<Map>()
            .map((e) => GenreModel.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        return Success(genres);
      } catch (_) {
        return const Success(<GenreEntity>[]);
      }
    }
    if (provider != null && provider.startsWith('an:')) {
      try {
        final list = await AniyomiChannel.getGenres(provider.substring(3));
        final genres = list
            .whereType<Map>()
            .map((e) => GenreModel.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        return Success(genres);
      } catch (_) {
        return const Success(<GenreEntity>[]);
      }
    }
    if (provider != null && provider.startsWith('my:')) {
      // Mangayomi exposes filters, not the app's flat genre list.
      return const Success(<GenreEntity>[]);
    }
    final jf = jellyfin;
    if (jf != null && provider != null && provider.startsWith('jf:')) {
      try {
        final list = await jf.genres(JellyfinBridge.bare(provider));
        return Success(list.map(GenreModel.fromJson).toList());
      } catch (_) {
        return const Success(<GenreEntity>[]);
      }
    }
    if (provider != null && provider.startsWith('mn:')) {
      try {
        final list = await MangaChannel.getGenres(provider.substring(3));
        final genres = list
            .whereType<Map>()
            .map((e) => GenreModel.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        return Success(genres);
      } catch (_) {
        return const Success(<GenreEntity>[]);
      }
    }
    try {
      final data = await dataSource.loadGenres();
      return Success(data);
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }
}
