import 'package:soplay/features/detail/domain/entities/episode_entity.dart';

/// Which episodes are loaded, and which one is playing.
///
/// A serial can run to hundreds of episodes, so the player holds a WINDOW of
/// them rather than the whole list. Two indices follow from that and the player
/// used to carry both as loose fields on a 832-line State, with the rule
/// connecting them written only in a comment:
///
///   * [index] is window-relative. It indexes [episodes] and it is what the
///     history write, the episode list and the next/prev buttons all use.
///   * [absoluteIndex] is the position in the SERIES. It is what decides
///     whether a next episode exists at all, and what a page fetch is keyed on.
///
/// Confusing the two is how "Next is greyed out at episode 100" happened: the
/// old test asked whether the next episode was in the loaded window, not
/// whether it existed in the series.
///
/// Immutable. A window that changes REPLACES itself rather than mutating,
/// because every index the player holds is relative to it — a list that grows
/// or shifts underneath those indices is worse than one that moves wholesale.
///
/// Pure: entities in, answers out. No Flutter, no getIt, no I/O.
class EpisodeWindow {
  const EpisodeWindow({
    required this.episodes,
    required this.windowStart,
    required this.index,
    required this.total,
    required this.isSerial,
  });

  /// The empty window a movie plays in, and what a serial starts from before
  /// its first page arrives.
  const EpisodeWindow.movie()
      : episodes = const [],
        windowStart = 0,
        index = 0,
        total = 0,
        isSerial = false;

  /// The loaded page. Never the whole series.
  final List<EpisodeEntity> episodes;

  /// The absolute index of `episodes[0]`.
  final int windowStart;

  /// Window-relative position of what is playing.
  final int index;

  /// Episodes in the SERIES, which is usually more than are loaded.
  final int total;

  final bool isSerial;

  /// Position in the series.
  int get absoluteIndex => windowStart + index;

  /// The episode playing, or null when the index does not name one — a movie,
  /// or a window that has not arrived yet.
  EpisodeEntity? get current =>
      (index >= 0 && index < episodes.length) ? episodes[index] : null;

  /// Whether a next episode EXISTS, which is not the same as it being loaded.
  ///
  /// This is the distinction the greyed-out Next button got wrong.
  bool get hasNext => isSerial && absoluteIndex + 1 < total;

  bool get hasPrev => isSerial && absoluteIndex > 0;

  /// Whether [windowIndex] names a loaded episode.
  bool contains(int windowIndex) =>
      windowIndex >= 0 && windowIndex < episodes.length;

  /// Whether [absolute] is a real episode of this series.
  bool containsAbsolute(int absolute) => absolute >= 0 && absolute < total;

  /// The 1-based page holding [absolute], for a pager of [pageSize].
  ///
  /// Returns null when paging cannot answer — a page size of zero, or an index
  /// outside the series. Callers treat null as "do not fetch".
  int? pageFor(int absolute, int pageSize) {
    if (pageSize <= 0 || !containsAbsolute(absolute)) return null;
    return absolute ~/ pageSize + 1;
  }

  /// The window after a page arrives. [page] is 1-based, as the API returns it.
  EpisodeWindow withPage(
    List<EpisodeEntity> fetched, {
    required int page,
    required int pageSize,
    required int absoluteIndex,
  }) {
    final start = (page - 1) * pageSize;
    return EpisodeWindow(
      episodes: List.of(fetched),
      windowStart: start,
      index: absoluteIndex - start,
      total: total,
      isSerial: isSerial,
    );
  }

  /// The same window with a different episode playing.
  EpisodeWindow at(int windowIndex) => EpisodeWindow(
        episodes: episodes,
        windowStart: windowStart,
        index: windowIndex,
        total: total,
        isSerial: isSerial,
      );

  /// The same window with a replaced episode list — a re-resolve that returned
  /// the same page, which is what a language switch does.
  EpisodeWindow withEpisodes(List<EpisodeEntity> next) => EpisodeWindow(
        episodes: List.of(next),
        windowStart: windowStart,
        index: index,
        total: total,
        isSerial: isSerial,
      );

  @override
  bool operator ==(Object other) =>
      other is EpisodeWindow &&
      other.windowStart == windowStart &&
      other.index == index &&
      other.total == total &&
      other.isSerial == isSerial &&
      // By identity: the session owns every allocation of this list, so a new
      // list is always a real change. A deep compare would be O(n) over up to
      // a hundred episodes on every rebuild.
      identical(other.episodes, episodes);

  @override
  int get hashCode =>
      Object.hash(identityHashCode(episodes), windowStart, index, total, isSerial);

  @override
  String toString() =>
      'EpisodeWindow(${episodes.length} loaded from $windowStart, '
      'at $index (abs $absoluteIndex of $total))';
}
