/// Every event this app is allowed to send, and its name on the wire.
///
/// ## Why an enum and not strings at the call site
///
/// Analytics rots in a very specific way: someone sends `video_play`, someone
/// else sends `play_video`, and six months later the funnel is silently
/// counting half the traffic. A closed set means the dashboard's event list is
/// this file, a rename is a compile error rather than a chart that quietly
/// flattens, and nobody can invent an event in a hurry.
///
/// ## What is deliberately absent
///
/// There is no event for what someone watched. Not the title, not the source,
/// not the search text. This app is used to watch things people would not
/// necessarily want recorded next to a device id, and the questions worth
/// answering — does search lead to playback, does the player fail more on one
/// engine, do people find the download button — are all answerable from counts
/// and outcomes. A title in an event log is a liability with no matching gain.
enum AnalyticsEvent {
  appOpened('app_opened'),

  // --- Finding something ---------------------------------------------------
  searchRan('search_ran'),
  searchEmpty('search_empty'),

  /// The escape hatch built for the "this source answered with something else"
  /// case actually being taken. If this is rare, the banner is not working.
  searchWidenedToAllSources('search_widened_to_all_sources'),
  searchSuggestionTapped('search_suggestion_tapped'),

  // --- Watching ------------------------------------------------------------
  playbackStarted('playback_started'),

  /// Reached the end. The ratio against [playbackStarted] is the one number
  /// that says whether playback actually works, as opposed to whether it
  /// starts.
  playbackCompleted('playback_completed'),
  playbackFailed('playback_failed'),
  sourceSwitched('source_switched'),

  // --- Everything else -----------------------------------------------------
  downloadQueued('download_queued'),
  extensionRepoAdded('extension_repo_added'),
  torrentStreamStarted('torrent_stream_started'),
  castStarted('cast_started');

  const AnalyticsEvent(this.wireName);

  /// The string Amplitude stores. Never change one: a renamed event orphans
  /// every chart built on it, and the old name keeps arriving from installs
  /// that have not updated.
  final String wireName;
}

/// Property keys, for the same reason the events are an enum.
///
/// Values must stay low-cardinality and non-identifying: a provider id, an
/// engine name, a failure category. Never a title, a url, a query or an
/// account.
abstract final class AnalyticsProp {
  static const String provider = 'provider';
  static const String engine = 'engine';
  static const String reason = 'reason';
  static const String surface = 'surface';
  static const String resultCount = 'result_count';
  static const String sourceCount = 'source_count';
  static const String kind = 'kind';
  static const String durationSeconds = 'duration_seconds';
}
