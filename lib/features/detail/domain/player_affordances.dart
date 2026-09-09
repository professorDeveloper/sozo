/// Which player controls apply right now.
///
/// The overlay and the settings sheet each worked this out for themselves, from
/// the same fields, a few hundred lines apart. Five of the six answers happened
/// to agree. The sixth did not, under a comment claiming it did:
/// `player_page.controls.dart` withheld Download until a stream had actually
/// resolved, `player_page.panels.dart` offered it immediately — so during a
/// load the bar hid the action and the sheet handed the viewer a download with
/// no url behind it.
///
/// One value object, two readers, no second copy to drift.
///
/// Deliberately pure: no Flutter, no getIt, no state. The inputs are counts and
/// flags the page already holds, so "which controls show" becomes a function
/// with a truth table instead of a condition spread over two files. There is a
/// test that keeps it importable without a widget tree.
class PlayerAffordances {
  const PlayerAffordances({
    required this.isSerial,
    required this.episodeCount,
    required this.serverCount,
    required this.serverSourceCount,
    required this.engineTrackCount,
    required this.langCount,
    required this.showDownloadAction,
    required this.provider,
    required this.hasResolvedUrl,
  });

  /// Nothing is available: what the bar renders before the first resolve, and
  /// the value a test starts from before switching one thing on.
  const PlayerAffordances.none()
      : isSerial = false,
        episodeCount = 0,
        serverCount = 0,
        serverSourceCount = 0,
        engineTrackCount = 0,
        langCount = 0,
        showDownloadAction = false,
        provider = '',
        hasResolvedUrl = false;

  final bool isSerial;

  /// Episodes in the loaded window — not in the series. A windowed serial with
  /// an empty window has nothing to list yet.
  final int episodeCount;

  /// Distinct hosts across the resolved sources.
  final int serverCount;

  /// Sources served by the host currently playing.
  final int serverSourceCount;

  /// Renditions the ENGINE reports inside the stream that is playing.
  ///
  /// Separate from [serverSourceCount] because they are different things: a
  /// rendition switch is instant and keeps the position, a source switch is a
  /// reload. Either one makes a quality control worth showing, and a stream can
  /// carry several renditions while the provider listed a single mirror — which
  /// is exactly the case a source-only count would hide the control for.
  final int engineTrackCount;

  /// Audio languages offered for the episode on screen.
  final int langCount;

  /// Whether this route was opened with downloading allowed at all.
  final bool showDownloadAction;

  final String provider;

  /// Whether a real stream url exists yet. A download needs the stream, not the
  /// placeholder the bar shows while loading.
  final bool hasResolvedUrl;

  /// The episode list is worth offering.
  bool get hasEpisodes => isSerial && episodeCount > 0;

  /// There is a choice of host — one host is not a choice.
  bool get hasServers => serverCount > 1;

  /// There is a quality to choose, from either place.
  bool get hasQualities => engineTrackCount > 0 || serverSourceCount > 1;

  /// This episode has more than one audio language.
  bool get hasLangs => langCount > 1;

  /// Downloading is possible right now.
  ///
  /// `uzmovi` is excluded because its urls are single-use and expire, so a
  /// downloaded file is a file that will not play.
  bool get canDownload =>
      showDownloadAction && provider != _kNoDownloadProvider && hasResolvedUrl;

  static const String _kNoDownloadProvider = 'uzmovi';

  PlayerAffordances copyWith({
    bool? isSerial,
    int? episodeCount,
    int? serverCount,
    int? serverSourceCount,
    int? engineTrackCount,
    int? langCount,
    bool? showDownloadAction,
    String? provider,
    bool? hasResolvedUrl,
  }) =>
      PlayerAffordances(
        isSerial: isSerial ?? this.isSerial,
        episodeCount: episodeCount ?? this.episodeCount,
        serverCount: serverCount ?? this.serverCount,
        serverSourceCount: serverSourceCount ?? this.serverSourceCount,
        engineTrackCount: engineTrackCount ?? this.engineTrackCount,
        langCount: langCount ?? this.langCount,
        showDownloadAction: showDownloadAction ?? this.showDownloadAction,
        provider: provider ?? this.provider,
        hasResolvedUrl: hasResolvedUrl ?? this.hasResolvedUrl,
      );
}
