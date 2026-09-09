import 'package:dio/dio.dart';

import 'package:soplay/features/extensions/domain/entities/catalog_source_entity.dart';
import 'package:soplay/features/extensions/domain/entities/extension_repo_entity.dart';

/// Reads the server-harvested source catalog.
///
/// Deliberately thin and cache-free where [ExtensionRepoRepository] caches: that
/// one serves a dozen curated rows that change monthly, this one serves a
/// filtered, paged slice of thousands and the filter changes with every chip
/// tap. The endpoint carries five minutes of edge cache, which is the right
/// place for it.
///
/// There is no compiled-in fallback either, and that is the honest shape: the
/// catalog IS the backend's answer. With the backend unreachable the page says
/// so, rather than pretending a stale snapshot is the current state of somebody
/// else's repos.
class CatalogRepository {
  CatalogRepository({required this.dio});

  final Dio dio;

  /// One page of sources.
  ///
  /// [languages] empty means no language filter — the server then returns
  /// everything, matching what an empty selection means everywhere else in the
  /// app. [runnableOnly] asks the server to drop sources this app cannot
  /// execute, which is how the Dart half of the Mangayomi repos stays out of a
  /// list where every row is meant to be installable.
  Future<CatalogPage> sources({
    List<String> languages = const [],
    ExtensionRepoKind? kind,
    CatalogItemType? itemType,
    String query = '',
    bool runnableOnly = false,
    bool nsfw = false,
    int page = 1,
    int limit = 50,
  }) async {
    final resp = await dio.get<dynamic>(
      '/catalog/sources',
      queryParameters: {
        if (languages.isNotEmpty) 'lang': languages.join(','),
        if (kind != null) 'kind': kind.wire,
        if (itemType != null) 'itemType': itemType.wire,
        if (query.trim().isNotEmpty) 'q': query.trim(),
        if (runnableOnly) 'runnable': 'true',
        if (nsfw) 'nsfw': 'true',
        'page': page,
        'limit': limit,
      },
    );
    final data = resp.data;
    final items = (data is Map ? data['items'] : null);
    return CatalogPage(
      items: items is List
          ? items
              .whereType<Map>()
              .map((e) => CatalogSourceEntity.fromJson(Map<String, dynamic>.from(e)))
              .whereType<CatalogSourceEntity>()
              .toList()
          : const [],
      page: (data is Map ? (data['page'] as num?)?.toInt() : null) ?? page,
      totalPages:
          (data is Map ? (data['totalPages'] as num?)?.toInt() : null) ?? 1,
      total: (data is Map ? (data['total'] as num?)?.toInt() : null) ?? 0,
    );
  }

  /// The language chips, with a count each.
  ///
  /// Asked of the server rather than derived from a page of results: a page is
  /// fifty rows out of thousands, and counting the languages in it would show
  /// the user a filter built from an arbitrary slice.
  Future<List<CatalogLanguage>> languages({
    ExtensionRepoKind? kind,
    CatalogItemType? itemType,
    bool runnableOnly = false,
    bool nsfw = false,
  }) async {
    final resp = await dio.get<dynamic>(
      '/catalog/languages',
      queryParameters: {
        if (kind != null) 'kind': kind.wire,
        if (itemType != null) 'itemType': itemType.wire,
        if (runnableOnly) 'runnable': 'true',
        if (nsfw) 'nsfw': 'true',
      },
    );
    final items = (resp.data is Map ? resp.data['items'] : null);
    if (items is! List) return const [];
    return [
      for (final e in items.whereType<Map>())
        if (((e['lang'] ?? '') as String).trim().isNotEmpty)
          CatalogLanguage(
            lang: (e['lang'] as String).trim().toLowerCase(),
            count: (e['count'] as num?)?.toInt() ?? 0,
            verified: (e['verified'] as num?)?.toInt() ?? 0,
          ),
    ];
  }
}

class CatalogPage {
  const CatalogPage({
    required this.items,
    required this.page,
    required this.totalPages,
    required this.total,
  });

  final List<CatalogSourceEntity> items;
  final int page;
  final int totalPages;
  final int total;

  bool get hasMore => page < totalPages;
}
