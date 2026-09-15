import 'package:flutter/widgets.dart';

/// A catalogue: a home screen with nothing to play.
///
/// Home has always been built from whichever source is current, which means
/// what you see is limited to what that one site carries and vanishes the day
/// it goes down. A catalogue is the other way round: AniList's or TMDB's view
/// of what exists, and when you open a title the app goes and finds a source
/// that has it. The catalogue stays up whether or not any source does.
///
/// It rides the same rail as a provider — its id is stored where the current
/// provider id is stored, and the home repository branches on the prefix the
/// way it already does for `cs:`, `an:`, `mn:` and `my:` — so nothing that
/// reads "the current source" had to learn a second concept. What it must
/// never be mistaken for is a source: it is not in the provider list, it has
/// no episodes, and asking it for a stream is a bug.
enum Catalogue {
  anilist('cat:anilist', 'catalogue.anilist', Color(0xFF3DB4F2)),
  tmdb('cat:tmdb', 'catalogue.tmdb', Color(0xFF01B4E4));

  const Catalogue(this.id, this.labelKey, this.accent);

  /// Persisted as the current provider id. Never rename one.
  final String id;
  final String labelKey;
  final Color accent;

  static const String prefix = 'cat:';

  static bool isId(String? providerId) =>
      providerId != null && providerId.startsWith(prefix);

  static Catalogue? fromId(String? providerId) {
    for (final c in values) {
      if (c.id == providerId) return c;
    }
    return null;
  }

  /// The part after the prefix, which is what the backend route takes.
  String get kind => id.substring(prefix.length);
}
