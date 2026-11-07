import 'package:soplay/features/detail/domain/entities/episode_entity.dart';

/// A run that a source lists as one, season after season.
///
/// A CloudStream series hands every season over in one list, each episode
/// numbered within its own season. The app tells episodes apart by number —
/// the download id, the history entry, the player's Next — so Lupin's five
/// seasons were five episode 1s, sorted in among each other ("Chapter 1",
/// "Chapter 6", "Chapter 1"…), and playing one marked the others watched.
abstract final class EpisodeSeasons {
  /// [episodes] with each one's season kept and its number made unique.
  ///
  /// When two seasons share a number the whole run is numbered 1, 2, 3… in
  /// season order — specials (season 0) last — and the source's own number
  /// moves to [EpisodeEntity.numberInSeason]. Season 1 keeps its numbers, so
  /// what was downloaded or watched of it before still lines up. A run whose
  /// seasons already number on (a second season starting at 13) keeps them.
  ///
  /// A list with fewer than two seasons comes back as it was, season dropped:
  /// "S1 E3" on a single-season show says nothing "3" does not.
  static List<EpisodeEntity> number(List<EpisodeEntity> episodes) {
    final seasons = {
      for (final e in episodes)
        if (e.season != null) e.season!,
    };
    if (seasons.length < 2) {
      if (!episodes.any((e) => e.season != null)) return episodes;
      return [for (final e in episodes) _with(e, e.episode, null, null)];
    }

    final indexed = [
      for (var i = 0; i < episodes.length; i++) (i, episodes[i]),
    ];
    indexed.sort((a, b) {
      var c = _seasonRank(a.$2.season).compareTo(_seasonRank(b.$2.season));
      if (c == 0) c = a.$2.episode.compareTo(b.$2.episode);
      if (c == 0) c = a.$1.compareTo(b.$1);
      return c;
    });

    final seen = <int>{};
    final collide = episodes.any((e) => !seen.add(e.episode));
    return [
      for (var i = 0; i < indexed.length; i++)
        _with(
          indexed[i].$2,
          collide ? i + 1 : indexed[i].$2.episode,
          indexed[i].$2.season,
          indexed[i].$2.episode,
        ),
    ];
  }

  /// The seasons in [episodes], in order, with how many episodes each has.
  static List<(int, int)> of(List<EpisodeEntity> episodes) {
    final counts = <int, int>{};
    for (final e in episodes) {
      final s = e.season;
      if (s != null) counts[s] = (counts[s] ?? 0) + 1;
    }
    final out = counts.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => _seasonRank(a.$1).compareTo(_seasonRank(b.$1)));
    return out;
  }

  /// Seasons ascending, the specials after the last one, and an episode the
  /// source gave no season after everything.
  static int _seasonRank(int? season) => switch (season) {
    null => 1 << 30,
    0 => (1 << 30) - 1,
    final s => s,
  };

  static EpisodeEntity _with(
    EpisodeEntity e,
    int episode,
    int? season,
    int? numberInSeason,
  ) => EpisodeEntity(
    episode: episode,
    label: e.label,
    mediaRef: e.mediaRef,
    availableLangs: e.availableLangs,
    hasSub: e.hasSub,
    hasDub: e.hasDub,
    image: e.image,
    airdate: e.airdate,
    runtime: e.runtime,
    overview: e.overview,
    webUrl: e.webUrl,
    scanlator: e.scanlator,
    season: season,
    numberInSeason: numberInSeason,
  );
}
