/// What AniList adds to a title's page beyond what any source knows.
///
/// A source's detail is what that site scraped: a title, a blurb, a poster.
/// AniList's is the record: how it is rated and where it ranks, who made it
/// and from what, and when the next episode lands. Present only on a page
/// that was built from AniList; null everywhere else, so nothing that renders
/// it has to guess whether the numbers are real.
class AniInfo {
  const AniInfo({
    required this.anilistId,
    this.malId,
    this.score,
    this.rankText,
    this.studio,
    this.source,
    this.format,
    this.status,
    this.episodes,
    this.tags = const [],
    this.nextEpisode,
    this.nextAiringAt,
  });

  final int anilistId;
  final int? malId;

  /// Out of 10, one decimal, from AniList's mean score out of 100.
  final double? score;
  final String? rankText;
  final String? studio;
  final String? source;
  final String? format;
  final String? status;
  final int? episodes;
  final List<String> tags;
  final int? nextEpisode;
  final DateTime? nextAiringAt;
}
