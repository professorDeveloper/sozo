import 'dart:async';

import 'package:dio/dio.dart';
import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/manga/manga_channel.dart';
import 'package:soplay/features/extensions/data/mangayomi_bridge.dart';
import 'package:soplay/features/jellyfin/data/jellyfin_bridge.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/js/js_runtime_service.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/search/data/model/genre_model.dart';
import 'package:soplay/features/search/data/model/search_model.dart';
import 'package:soplay/features/search/domain/repositories/search_repository.dart';
import 'package:soplay/features/search/domain/services/cross_search_engine.dart';

import '../datasources/search_data_source.dart';

class SearchRepositoryImp extends SearchRepository
    implements CatalogueSearchRepository {
  final SearchDataSource dataSource;
  final JsRuntimeService? jsRuntime;
  final HiveService? hive;

  SearchRepositoryImp({
    required this.dataSource,
    required this.mangayomi,
    this.jellyfin,
    this.jsRuntime,
    this.hive,
  });

  final MangayomiBridge mangayomi;
  final JellyfinBridge? jellyfin;

  String? get _currentProvider {
    final id = hive?.getCurrentProvider();
    return (id == null || id.isEmpty) ? null : id;
  }

  @override
  Future<Result<List<GenreModel>>> getDiscoveryGenres(String type) async {
    try {
      return Success(
        await dataSource.getCatalogueGenres(catalogueKind!, type: type),
      );
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  String? get catalogueKind => Catalogue.fromId(_currentProvider)?.kind;

  @override
  Future<Result<SearchModel>> discover(
    Map<String, String> filters, {
    int page = 1,
  }) async {
    final kind = catalogueKind;
    if (kind == null) return Failure(Exception("Select a catalogue"));
    try {
      return Success(
        await dataSource.discoverCatalogue(kind, filters, page: page),
      );
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
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
    // Extension hosts DO have genres, and Home has drawn them for a long time
    // (see HomeRepositoryImp.loadGenres). Search returned an empty list for
    // every one of them, so the Categories section was simply absent on the
    // Search tab for the large majority of the installed sources — and on a
    // device with no recent searches the landing screen fell all the way
    // through to "nothing to browse", on a source whose Home screen was
    // showing those very genres one tab away.
    //
    // Mangayomi is the one genuine exception: it exposes per-source filters
    // rather than the flat genre list this screen draws, so it still has
    // nothing to offer here.
    if (provider != null && provider.startsWith('my:')) {
      return const Success(<GenreModel>[]);
    }
    final jf = jellyfin;
    if (jf != null && provider != null && provider.startsWith('jf:')) {
      try {
        final list = await jf
            .genres(JellyfinBridge.bare(provider))
            .timeout(_hostBudget);
        return Success(list.map(GenreModel.fromJson).toList());
      } catch (e) {
        return Failure(Exception(jf.describe(e)));
      }
    }
    final hostGenres = switch (provider) {
      final p? when p.startsWith('cs:') => CloudStreamChannel.getGenres,
      final p? when p.startsWith('an:') => AniyomiChannel.getGenres,
      final p? when p.startsWith('mn:') => MangaChannel.getGenres,
      _ => null,
    };
    if (hostGenres != null && provider != null) {
      try {
        final list = await hostGenres(
          provider.substring(3),
        ).timeout(_hostBudget);
        return Success([
          for (final e in list.whereType<Map>())
            GenreModel.fromJson(Map<String, dynamic>.from(e)),
        ]);
      } catch (e) {
        // A host that cannot list genres is not a broken screen: the rail and
        // the recents above are still worth showing. Reported rather than
        // swallowed, so the row can say the categories did not load instead of
        // vanishing.
        return Failure(Exception(e.toString()));
      }
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
      final provider = _currentProvider;
      final catalogue = Catalogue.fromId(provider);
      if (catalogue != null) {
        return Success(
          await dataSource.getCatalogueGenre(catalogue.kind, genre, page: page),
        );
      }
      // The other half of showing an extension source's genres: the tile has
      // to lead somewhere. A `cs:`/`an:`/`mn:` genre browsed through the
      // backend would be GET /contents/genre/<the extension's own slug>
      // against a provider id the server has never heard of. `getSection` is
      // how Home browses exactly these, and it answers in the same shape.
      final section = switch (provider) {
        final p? when p.startsWith('cs:') => CloudStreamChannel.getSection,
        final p? when p.startsWith('an:') => AniyomiChannel.getSection,
        final p? when p.startsWith('mn:') => MangaChannel.getSection,
        _ => null,
      };
      final jf = jellyfin;
      if (jf != null && provider != null && provider.startsWith('jf:')) {
        final map = await jf
            .getSection(
              JellyfinBridge.bare(provider),
              'genre:$genre',
              page: page,
            )
            .timeout(_hostBudget);
        return Success(SearchModel.fromJson(map));
      }
      if (section != null && provider != null) {
        final map = await section(
          provider.substring(3),
          genre,
          page: page,
        ).timeout(_hostBudget);
        return Success(SearchModel.fromJson(map));
      }
      return Success(await dataSource.getMoviesByGenre(genre, page: page));
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
        () =>
            CloudStreamChannel.search(provider.substring(3), query, page: page),
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
    final jf = jellyfin;
    if (jf != null && provider != null && provider.startsWith('jf:')) {
      return _viaHost(
        'Jellyfin',
        () => jf.search(JellyfinBridge.bare(provider), query, page: page),
      );
    }
    // Why the JS extractor said no, when it said no at all. Kept so that if
    // the backend cannot answer either, the reader is told the real reason —
    // a Cloudflare challenge, say — instead of whatever Dio then reports.
    Object? jsFailure;
    if (js != null && provider != null) {
      // The JS runtime falls THROUGH to the backend when it has no answer, so
      // it cannot use _viaHost — but it can still be bounded.
      try {
        final map = await js
            .trySearch(provider, query, page)
            .timeout(_hostBudget);
        if (map != null) return Success(SearchModel.fromJson(map));
      } on TimeoutException {
        jsFailure = Exception(
          '$provider: no answer after ${_hostBudget.inSeconds}s',
        );
      } catch (e) {
        // A THROW used to end the search here, while a null fell through to
        // the backend — two outcomes that mean the same thing to the reader,
        // given opposite treatment. So a Cloudflare challenge that survived
        // the one retry, a CDN hiccup fetching the extractor, or an extractor
        // that simply has no search() turned the Search tab red for a provider
        // the backend could have answered perfectly well. ProviderManager does
        // the opposite for these same providers when resolving media: it logs
        // and falls back to the server. This is now the same policy.
        jsFailure = e;
      }
    }
    try {
      final result = await dataSource.searchMovies(query, page: page);
      return Success(result);
    } catch (e) {
      // Both legs failed. The extractor's reason is the more specific one and
      // the one the reader can act on, so it wins.
      return Failure(Exception((jsFailure ?? e).toString()));
    }
  }
}
