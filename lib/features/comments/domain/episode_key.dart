/// Names an episode within a title for its comment thread and reactions.
///
/// The same number watch history keys an episode by — `episodeNumber`, else
/// the index — so "have I finished this one" and "what do people say about
/// it" agree on which episode is meant. Null for a film: its comments are the
/// title's comments.
class EpisodeKey {
  const EpisodeKey._();

  static const String _prefix = 'e';

  static String? of({
    required bool isSerial,
    int? episodeNumber,
    int? episodeIndex,
  }) {
    if (!isSerial) return null;
    final n = episodeNumber ?? episodeIndex;
    if (n == null || n < 0) return null;
    return '$_prefix$n';
  }

  /// The episode number inside [key], or null when it is not one of ours.
  static int? numberOf(String? key) {
    if (key == null || !key.startsWith(_prefix)) return null;
    return int.tryParse(key.substring(_prefix.length));
  }

  /// What a reaction is filed under: a film reacts under the empty key.
  static String forReactions(String? key) => key ?? '';
}
