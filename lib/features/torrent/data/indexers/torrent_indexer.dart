import 'package:dio/dio.dart';
import 'package:soplay/features/torrent/domain/entities/torrent_result.dart';

/// A portable content category, mapped onto each tracker's own codes.
///
/// Trackers do not agree on categories — Nyaa uses `1_2`, Tokyo Toshokan uses
/// a numeric `type`, nekoBT has none at all. The search UI works in these
/// terms and each indexer translates.
enum TorrentCategory {
  /// No category restriction.
  all,

  /// Everything under Nyaa's Anime tree.
  anime,

  /// English-subtitled anime — Nyaa `1_2`. The default for most users.
  animeEnglish,

  /// Subtitled or dubbed in a language other than English — Nyaa `1_3`.
  animeNonEnglish,

  /// Japanese audio with no subs, Japanese subs, or bilingual — Nyaa `1_4`.
  animeRaw,

  /// Anime OP/ED and fan-made MVs — Nyaa `1_1`.
  animeMusicVideo,

  /// Live-action film and drama — Nyaa `4_0`.
  liveAction,
}

/// Which uploads the tracker should return.
enum TorrentFilter {
  none,

  /// Hide re-uploads and modifications of other people's releases.
  noRemakes,

  /// Only uploads from accounts the tracker's staff vouch for — the green rows
  /// on Nyaa. A profile-level flag, so it says who uploaded it, not how good
  /// the encode is.
  trustedOnly,
}

enum TorrentSort {
  /// Newest first.
  date,

  /// Most seeders first. The right default for streaming, where a dead swarm
  /// is a hard failure rather than a slow download.
  seeders,

  size,

  /// Most completed downloads.
  downloads,
}

/// One search request, in tracker-independent terms.
class TorrentQuery {
  const TorrentQuery({
    required this.term,
    this.category = TorrentCategory.animeEnglish,
    this.filter = TorrentFilter.none,
    this.sort = TorrentSort.seeders,
    this.page = 1,
  });

  final String term;
  final TorrentCategory category;
  final TorrentFilter filter;
  final TorrentSort sort;

  /// 1-based. Trackers that cannot paginate ignore anything above 1 and the
  /// repository stops asking them.
  final int page;

  TorrentQuery copyWith({
    String? term,
    TorrentCategory? category,
    TorrentFilter? filter,
    TorrentSort? sort,
    int? page,
  }) =>
      TorrentQuery(
        term: term ?? this.term,
        category: category ?? this.category,
        filter: filter ?? this.filter,
        sort: sort ?? this.sort,
        page: page ?? this.page,
      );
}

/// A single torrent tracker Sozo can search.
///
/// Implementations must never throw for an ordinary failure — a tracker being
/// down, rate-limiting us, or changing its markup is expected, and one dead
/// tracker must not empty the whole result list. Return an empty list instead;
/// [TorrentSearchRepository] merges what it gets.
abstract class TorrentIndexer {
  const TorrentIndexer();

  /// Stable id, persisted in settings when the user enables or disables a
  /// tracker. Never rename one of these.
  String get id;

  /// Display name for the badge on each result row.
  String get name;

  /// Where the tracker lives, for "open in browser" and for resolving the
  /// relative links its HTML hands back.
  Uri get baseUri;

  /// Adult-only trackers stay hidden unless the user has opted in, matching
  /// how the rest of the app gates NSFW sources.
  bool get isNsfw => false;

  /// Whether this tracker can serve pages beyond the first.
  bool get supportsPagination => true;

  /// Categories this tracker understands. A query for anything else is
  /// answered with an empty list rather than a wrong one.
  Set<TorrentCategory> get categories => const {TorrentCategory.all};

  Future<List<TorrentResult>> search(
    TorrentQuery query, {
    CancelToken? cancelToken,
  });
}
