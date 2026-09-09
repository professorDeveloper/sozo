import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/search/domain/services/search_relevance.dart';

/// How a provider is searched. Decides the dispatch path in [CrossSearchEngine].
enum ProviderKind {
  /// On-device extension host: Kotlin (`cs:` / `an:` / `mn:`) or the
  /// JavaScript runtime (`my:`). Both run entirely on the device and may need
  /// to fetch the extension itself before the first call, which is why they
  /// share the engine's longer per-provider budget.
  channel,

  /// On-device full-scope JS extractor.
  js,

  /// Backend (`/contents/search`) — provider-agnostic; collapses to one call.
  server,
}

/// Outcome of one provider's search leg.
enum ProviderSearchStatus { ok, empty, timeout, error }

/// A lightweight, UI-facing handle to a provider participating in cross-search.
class ProviderRef {
  const ProviderRef({
    required this.id,
    required this.name,
    required this.kind,
    this.image,
  });

  final String id;
  final String name;
  final String? image;
  final ProviderKind kind;

  static ProviderKind kindOf(String id, {required bool scopesAll}) {
    if (id.startsWith('cs:') ||
        id.startsWith('an:') ||
        id.startsWith('mn:') ||
        id.startsWith('my:')) {
      return ProviderKind.channel;
    }
    return scopesAll ? ProviderKind.js : ProviderKind.server;
  }

  factory ProviderRef.fromEntity(ProviderEntity p) => ProviderRef(
        id: p.id,
        name: p.name,
        image: p.image.isEmpty ? null : p.image,
        kind: kindOf(p.id, scopesAll: p.scopesAll),
      );
}

/// One provider's search result (may be empty / timed-out / errored).
class ProviderSearchResult {
  const ProviderSearchResult({
    required this.provider,
    required this.items,
    required this.status,
    this.page = 1,
    this.totalPages = 1,
    this.message = '',
  });

  final ProviderRef provider;
  final List<MovieEntity> items;
  final ProviderSearchStatus status;
  final int page;
  final int totalPages;

  /// Why this leg failed, when it did. Shown next to the source's name instead
  /// of being reduced to a count of anonymous failures.
  final String message;

  bool get hasItems => items.isNotEmpty;
  bool get hasMore => page < totalPages;

  ProviderSearchResult copyWith({
    List<MovieEntity>? items,
    ProviderSearchStatus? status,
    int? page,
    int? totalPages,
    String? message,
  }) =>
      ProviderSearchResult(
        provider: provider,
        items: items ?? this.items,
        status: status ?? this.status,
        page: page ?? this.page,
        totalPages: totalPages ?? this.totalPages,
        message: message ?? this.message,
      );
}

/// One source's copy of a title.
class TitleHit {
  const TitleHit({required this.provider, required this.item});

  final ProviderRef provider;
  final MovieEntity item;
}

/// The same title as carried by one or more sources.
///
/// This is the whole point of cross-search: without it the user has to scroll
/// N per-source rails to discover that one title is on N sources.
class MergedSearchTitle {
  MergedSearchTitle({required this.key, required this.hits, this.year});

  final String key;
  final List<TitleHit> hits;
  final int? year;

  MovieEntity get primary => hits.first.item;
  ProviderRef get primaryProvider => hits.first.provider;
  int get sourceCount => hits.map((h) => h.provider.id).toSet().length;
}

/// Title key used to merge hits across sources: lowercased, punctuation and a
/// trailing "(year)" removed, leading article dropped, whitespace collapsed.
String normalizedTitleKey(String title) {
  var t = title.toLowerCase().trim();
  t = t.replaceAll(RegExp(r'[\(\[]\s*(19|20)\d{2}\s*[\)\]]'), ' ');
  t = t.replaceAll(RegExp(r"[^a-z0-9\u0400-\u04ff\u0600-\u06ff ]+"), ' ');
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  for (final article in const ['the ', 'a ', 'an ']) {
    if (t.startsWith(article)) {
      t = t.substring(article.length);
      break;
    }
  }
  return t;
}

/// Groups every leg's items into one list of titles.
///
/// Two hits merge when their [normalizedTitleKey] matches and their years are
/// compatible — equal, or missing on at least one side, because extension hosts
/// almost never populate a year.
///
/// [query] decides the order. Without it the list was sorted by how many
/// sources carried a title, which sounds like popularity and is not: two
/// sources that both pad their results with the same unrelated film outranked
/// the one source holding an exact match. Relevance leads, and the source count
/// breaks ties among titles that answer the query equally well — which is where
/// it was always a good signal.
List<MergedSearchTitle> mergeSearchResults(
  List<ProviderSearchResult> legs, {
  String query = '',
}) {
  final groups = <String, List<MergedSearchTitle>>{};
  final ordered = <MergedSearchTitle>[];

  for (final leg in legs) {
    for (final item in leg.items) {
      final key = normalizedTitleKey(item.title);
      if (key.isEmpty) continue;
      final bucket = groups.putIfAbsent(key, () => <MergedSearchTitle>[]);
      final match = bucket
          .where((g) => g.year == null || item.year == null || g.year == item.year)
          .firstOrNull;
      if (match == null) {
        final group = MergedSearchTitle(
          key: key,
          year: item.year,
          hits: [TitleHit(provider: leg.provider, item: item)],
        );
        bucket.add(group);
        ordered.add(group);
      } else {
        match.hits.add(TitleHit(provider: leg.provider, item: item));
      }
    }
  }

  // Ties keep arrival order: a rail that reorders under the user's finger is
  // how a tap lands on a different title than the one that was under it.
  //
  // A group is scored by its best hit, not its first. Sources title the same
  // show differently — "Naruto Shippuden" on one, "Naruto: Shippuuden" on
  // another — and the merged card should be ranked by whichever of those the
  // query actually matched.
  final indexed = [
    for (var i = 0; i < ordered.length; i++)
      (
        index: i,
        group: ordered[i],
        score: query.isEmpty
            ? 0.0
            : ordered[i].hits.fold<double>(
                  0,
                  (best, h) {
                    final s = SearchRelevance.score(h.item.title, query);
                    return s > best ? s : best;
                  },
                ),
      ),
  ]..sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byCount = b.group.sourceCount.compareTo(a.group.sourceCount);
      return byCount != 0 ? byCount : a.index.compareTo(b.index);
    });
  return [for (final e in indexed) e.group];
}
