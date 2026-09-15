/// What a catalogue knows about a title that a source does not.
///
/// A source's detail is what that site scraped: a title, a blurb, a poster.
/// A catalogue's is the record — AniList's or TMDB's: how it is rated, who
/// made it, what it cost, when the next episode lands. Present only on a page
/// that was built from a catalogue; null everywhere else, so nothing that
/// renders it has to guess whether the numbers are real.
///
/// [facts] is what the About tab shows, already worded: a label key and a
/// value. Each catalogue decides its own — a studio and a source for an anime,
/// a studio and a box office for a film — and the tab draws whatever it is
/// given. The typed fields are the few the header reads directly.
class RecordInfo {
  const RecordInfo({
    this.anilistId,
    this.malId,
    this.tmdbId,
    this.score,
    this.nextEpisode,
    this.nextAiringAt,
    this.facts = const [],
    this.tags = const [],
  });

  final int? anilistId;
  final int? malId;
  final int? tmdbId;

  /// Out of 10, one decimal.
  final double? score;
  final int? nextEpisode;
  final DateTime? nextAiringAt;
  final List<RecordFact> facts;
  final List<String> tags;
}

class RecordFact {
  const RecordFact(this.labelKey, this.value);

  final String labelKey;
  final String value;
}
