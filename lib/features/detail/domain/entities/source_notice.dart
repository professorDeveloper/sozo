/// Why a source cannot play a title, as the backend states it.
///
/// A source refusing one title is not a failure of the app, of the network or
/// of the title: it is a fact about that source, and the backend now says which
/// fact in a field instead of leaving it to be guessed from a sentence. The app
/// used to throw the whole body away and show "Video URL aniqlanmadi" — a
/// technical phrase, in Uzbek, whatever had actually happened and whatever
/// language the viewer reads — so a title the site had simply moved into its own
/// app looked like a bug in Sozo.
///
/// The code reaches the app two ways, because the two endpoints differ. The
/// episodes response carries it as a field (`noticeCode`, and `playableReason`
/// beside `playable: false`). A failed media resolve carries it at the head of
/// the message string, `SOURCE_MOVED_TO_APP: ...`, because the API's error
/// handler serialises only `message` — see `mediaError` in
/// sozo-backend/src/providers/asilmedia.js, which repeats the code there for
/// exactly this reason. [read] accepts both shapes so neither caller has to
/// know which it is holding.
enum SourceNotice {
  /// The site now sells its own app for this title and keeps no player on the
  /// page. Nothing is left to resolve: another source is the only way to watch.
  movedToApp('SOURCE_MOVED_TO_APP'),

  /// The page carries no player, and no promotion either — a record of a title
  /// the source does not actually host.
  noPlayer('SOURCE_NO_PLAYER'),

  /// A serial's page was resolved as a film. The episodes exist and resolve
  /// perfectly; they are reached through the episode list rather than here, so
  /// this one is a wrong turn rather than a dead end.
  isSeries('SOURCE_IS_SERIES');

  const SourceNotice(this.code);

  /// The token the backend sends. Stable: it crosses the HTTP boundary inside a
  /// message string as well as in a field.
  final String code;

  /// What the viewer is told, in their own language.
  String get messageKey => switch (this) {
    SourceNotice.movedToApp => 'detail.notice_moved_to_app',
    SourceNotice.noPlayer => 'detail.notice_no_player',
    SourceNotice.isSeries => 'detail.notice_is_series',
  };

  /// Whether this source can play this title at all.
  ///
  /// False for the two dead ends, and true for [isSeries]: the episodes are
  /// there, so hiding Play would take away the one affordance that works.
  bool get playable => this == SourceNotice.isSeries;

  /// The notice [raw] names, or null when it names none.
  ///
  /// Accepts the bare code and a message that begins with it, so the same call
  /// serves `noticeCode`, `playableReason` and a 422 body's `message`. Anything
  /// unrecognised is null rather than a guess — a code this app has not been
  /// taught is better shown as the plain failure it was than explained wrongly.
  static SourceNotice? read(String? raw) {
    if (raw == null) return null;
    final head = raw.trim().split(':').first.trim();
    if (head.isEmpty) return null;
    for (final notice in values) {
      if (notice.code == head) return notice;
    }
    return null;
  }
}

/// A playback failure that carries its reason.
///
/// Thrown as the error of a `Failure` so the page can branch on the reason
/// rather than parse the sentence it would otherwise have had to print. The
/// message is still a sentence, for a log or a screen that has not been taught
/// this type.
class SourceNoticeException implements Exception {
  const SourceNoticeException(this.notice, {this.providerNotice});

  final SourceNotice notice;

  /// What the site itself printed where the player used to be, in the site's
  /// own words and language. Never shown to the viewer — it is the source's
  /// advertisement, not an explanation — but it is what a maintainer reading a
  /// log needs to see why a title was gated.
  final String? providerNotice;

  @override
  String toString() => 'SourceNoticeException(${notice.code})';
}
