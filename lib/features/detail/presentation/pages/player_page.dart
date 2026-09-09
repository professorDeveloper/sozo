import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:soplay/core/analytics/analytics.dart';
import 'package:soplay/core/player/color_profile.dart';
import 'package:soplay/core/player/shader_presets.dart';
import 'package:soplay/core/player/shader_store.dart';
import 'package:soplay/features/detail/data/title_prefs_store.dart';
import 'package:soplay/features/stats/data/watch_stats_store.dart';
import 'package:soplay/core/network/user_agent.dart';
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:floating/floating.dart';
import 'package:gal/gal.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:dart_cast/dart_cast.dart';
import 'package:soplay/core/cast/cast_controller.dart';
import 'package:soplay/core/cast/cast_handoff.dart';
import 'package:soplay/core/subtitles/subtitle_auto_translate.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/discord/discord_activity.dart';
import 'package:soplay/core/discord/discord_presence_service.dart';
import 'package:soplay/core/diagnostics/log_viewer_sheet.dart';
import 'package:soplay/core/diagnostics/player_log.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/player/external_player.dart';
import 'package:soplay/core/player/local_hls_proxy.dart';
import 'package:soplay/core/player/player_engine.dart';
import 'package:soplay/core/player/player_video_track.dart';
import 'package:soplay/core/player/source_ladder.dart';
import 'package:soplay/features/detail/domain/download_choices.dart';
import 'package:soplay/features/detail/domain/player_affordances.dart';
import 'package:soplay/features/detail/domain/playback/episode_window.dart';
import 'package:soplay/features/detail/domain/playback/playback_fault.dart';
import 'package:soplay/features/detail/domain/playback/retry_policy.dart';
import 'package:soplay/features/detail/domain/playback/skip_offers.dart';
import 'package:soplay/features/detail/domain/playback/watch_progress.dart';
import 'package:soplay/features/detail/domain/player_controls_layout.dart';
import 'package:soplay/features/detail/domain/playback/party_rules.dart';
import 'package:soplay/features/detail/domain/playback/player_info_fields.dart';
import 'package:soplay/features/detail/domain/playback/playback_readout.dart';
import 'package:soplay/core/player/stream_warnings.dart';
import 'package:soplay/core/player/webview_stream_extractor.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/widgets/server_badge.dart';
import 'package:soplay/core/system/app_orientation.dart';
import 'package:soplay/core/system/desktop_window.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/anilist/data/anilist_tracker.dart';
import 'package:soplay/features/mal/data/mal_tracker.dart';
import 'package:soplay/features/cloudflare/cloudflare_solver.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/entities/media_resolve_entity.dart';
import 'package:soplay/features/detail/domain/usecases/get_episodes_usecase.dart';
import 'package:soplay/features/detail/domain/entities/extractor_config_entity.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';
import 'package:soplay/core/subtitles/online_subtitles_service.dart';
import 'package:soplay/core/subtitles/subtitle_translation_service.dart';
import 'package:soplay/core/subtitles/subtitle_parser.dart';
import 'package:soplay/features/detail/domain/entities/subtitle_entity.dart';
import 'package:soplay/features/detail/domain/entities/subtitle_style.dart';
import 'package:soplay/features/detail/domain/entities/thumbnails_entity.dart';
import 'package:soplay/core/preview/frame_preview_service.dart';
import 'package:soplay/features/detail/domain/entities/video_source_entity.dart';
import 'package:soplay/features/detail/domain/video_option_groups.dart';
import 'package:soplay/features/detail/domain/usecases/resolve_media_usecase.dart';
import 'package:soplay/features/detail/data/aniskip_service.dart';
import 'package:soplay/features/detail/presentation/pages/player_controls_page.dart';
import 'package:soplay/features/detail/presentation/widgets/alternate_source_sheet.dart';
import 'package:soplay/features/detail/presentation/widgets/player_info_fields_sheet.dart';
import 'package:soplay/features/streak/data/streak_service.dart';
import 'package:soplay/features/streak/presentation/dialogs/streak_milestone_dialog.dart';
import 'package:soplay/features/download/domain/entities/download_request.dart';
import 'package:soplay/features/download/domain/usecases/enqueue_download_usecase.dart';
import 'package:soplay/features/download/presentation/download_messages.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';
import 'package:soplay/features/watch_party/data/watch_party_service.dart';
import 'package:soplay/features/watch_party/domain/party_resolve_gate.dart';
import 'package:soplay/features/watch_party/presentation/widgets/party_plugin_required_view.dart';
import 'package:soplay/features/watch_party/domain/entities/party_content.dart';
import 'package:soplay/features/watch_party/domain/entities/party_playback.dart';
import 'package:soplay/features/watch_party/domain/entities/party_state.dart';
import 'package:soplay/features/watch_party/presentation/party_entry.dart';
import 'package:soplay/features/watch_party/presentation/widgets/party_reactions_bar.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:soplay/core/player/media_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:soplay/features/history/data/history_sync_service.dart';
import 'package:soplay/features/live_tv/presentation/widgets/live_guide_sheet.dart';
import 'package:soplay/core/torrent/torrent_engine.dart';
import 'package:soplay/core/torrent/torrent_stream_url.dart';
import 'package:soplay/features/torrent/presentation/torrent_playback.dart';
import 'package:soplay/features/torrent/presentation/widgets/torrent_stats_overlay.dart';

part 'player_page.models.dart';
part 'player_page.widgets.dart';
part 'player_page.media.dart';
part 'player_page.controls.dart';
part 'player_page.panels.dart';
part 'player_page.subtitles.dart';
part 'player_page.gestures.dart';
part 'player_page.history.dart';
part 'player_page.pip.dart';
part 'player_page.sleep.dart';
part 'player_page.cast.dart';
part 'player_page.aniskip.dart';
part 'player_page.party.dart';
part 'player_page.tv.dart';

/// Hard ceiling on auto-retries per episode — see [_PlayerPageState._lifetimeRetries].
const int _kMaxLifetimeRetries = RetryPolicy.maxLifetimeRetries;

/// Reconnect budget for a live broadcast, which is a different problem.
///
/// A film either plays or is broken, so four attempts in a session is generous.
/// A channel drops — a segment gap, a CDN failing over, a phone changing
/// network — and the only correct response is to reconnect and keep watching.
/// Four in a two-hour evening meant the player gave up permanently on something
/// that was working again seconds later.
const int _kMaxLiveRetries = RetryPolicy.maxLiveRetries;

/// How long to wait before reconnecting a dropped channel, by attempt.
///
/// Fast enough that a blip is invisible, and backing off so a channel that is
/// genuinely off air is not hammered all evening.
Duration _liveRetryBackoff(int attempt) => RetryPolicy.liveBackoff(attempt);

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.args});
  final PlayerArgs args;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final ResolveMediaUseCase _resolve = getIt<ResolveMediaUseCase>();
  final HiveService _hive = getIt<HiveService>();
  final HistoryService _history = getIt<HistoryService>();
  final Floating _floating = Floating();

  // Playback preferences, snapshotted in initState. Settings → Player is not
  // reachable while the player is open, so re-reading Hive would only cost —
  // and _onPanUpdate runs on every drag frame, where a per-frame box lookup is
  // exactly the kind of thing that shows up as jank.
  late final int _seekSeconds;
  late final double _longPressBoost;
  late final bool _brightnessGestureEnabled;
  late final bool _volumeGestureEnabled;

  /// How far one double-tap / seek-button / arrow-key press jumps.
  Duration get _seekStep => Duration(seconds: _seekSeconds);

  /// AniSkip: opening/ending intervals for the CURRENT episode, the offer
  /// currently on screen, and which types have already been used or declined.
  /// Which skip offer belongs on screen, and which have been used.
  ///
  /// Was `_skipIntervals` plus a `_skipsTaken` set, with the ten-second offer
  /// window as a private constant on an extension. See [SkipOffers].
  final SkipOffers _skips = SkipOffers();
  SkipInterval? _activeSkip;

  /// Sleep timer: the moment playback should stop, or null when unarmed.
  /// [_sleepAtEpisodeEnd] is the other arming mode — see player_page.sleep.dart.
  Timer? _sleepTicker;
  DateTime? _sleepDeadline;
  bool _sleepAtEpisodeEnd = false;

  bool _isPip = false;
  bool _resumeAfterPause = false;
  bool _lastPipPlaying = false;

  PlayerController? _controller;
  String? _currentQuality;
  String? _videoUrl;
  String? _mediaType;

  /// Torrent playback, when the source turned out to be a magnet rather than a
  /// stream. The engine is lazy — constructing it costs nothing and it never
  /// touches the native side unless a torrent link actually arrives.
  final TorrentEngine _torrentEngine = TorrentEngine();

  /// Hash of the torrent currently being streamed, so leaving the player can
  /// close the swarm connection. Without this the device keeps uploading to
  /// strangers after the viewer thinks they are done watching.
  String? _torrentHash;
  Map<String, String> _headers = const {};
  bool _isNetworkVideo = false;
  bool _isHls = false;
  /// True while the current media is a live broadcast.
  ///
  /// Seeded from what the caller SAID it is rather than guessed alone: Live TV
  /// hands the player `type: 'live'`, and a stream that is live does not stop
  /// being live because its playlist happens to report a duration. Plenty of
  /// live HLS carries a sliding DVR window, so the duration heuristic below
  /// says "not live" for real channels — which drew a scrub bar on something
  /// unscrubbable, ran frame-preview extraction against an endless stream, and
  /// treated the live edge as the end of the file.
  bool _isLive = false;
  List<VideoSourceEntity> _videoSources = const [];

  /// Server-sent headless-WebView sniff directive for the CURRENT media, or null.
  ///
  /// Held as state rather than threaded through [_initializeWith]'s eight call
  /// sites: quality switches, party sync and retries all re-enter that method
  /// and every one of them needs the same directive.
  ///
  /// It is a capability description, never a provider name — a source whose real
  /// manifest only exists once the page's own JS has run carries this, and the
  /// player treats them all identically. Adding such a provider is a backend-only
  /// change.
  ExtractorConfigEntity? _extractorConfig;
  int _currentSourceIndex = -1;

  /// Mirrors already attempted for what is on screen, by url.
  ///
  /// This was a single `_autoFallbackUsed` bool, which is why a five-mirror
  /// title gave up after the second: one fallback, latched. Urls rather than
  /// indices because `_loadEpisode` REBUILDS the candidate list on every
  /// re-resolve, and the retry path re-resolves — an index does not survive
  /// that, so the walk used to restart at the top and loop.
  final Set<String> _triedSourceUrls = <String>{};

  /// Set when a mirror failed to DECODE, so sibling mirrors in the same codec
  /// sink to the back of the ladder. Cleared wherever the ladder resets.
  String? _decoderAvoidCodec;
  /// Pinch zoom over the video, 1.0 = untouched.
  ///
  /// Separate from [_PlayerFit], which snaps to three presets. Fit answers
  /// "how should this frame sit in this window"; zoom answers "I want to crop
  /// these bars away by exactly this much", which no preset can. Session-only
  /// and reset on every new episode — a crop tuned for a 2.39:1 film is wrong
  /// for the 16:9 episode after it.
  double _videoZoom = 1.0;

  /// The zoom the current pinch started from, so a gesture scales relative to
  /// where it began rather than snapping back to 1.0 on every touch.
  double _zoomAtPinchStart = 1.0;

  /// Whether the live readout is on screen. Session-only on purpose: it is a
  /// diagnostic, and nobody wants to find it still there next week.
  bool _showPlayerInfo = false;

  /// Whether the automatic translation attempt has been made for the episode
  /// on screen. Per episode, not per session — reset in _resetForEpisode.
  bool _autoTranslateDone = false;

  /// Which rows the info overlay may show. Read once at open and updated when
  /// the picker changes it, rather than re-read on every frame — the overlay
  /// rebuilds on every position tick and a Hive read there is pure waste.
  Set<String> _infoFields =
      PlayerInfoFields.fromStored(getIt<HiveService>().getPlayerInfoFields());

  /// The viewer's bar arrangement. Read once at open: it can only change from
  /// the editor, and returning from that re-reads it.
  PlayerControlsLayout _layout = PlayerControlsLayout.fromStored(
    getIt<HiveService>().getPlayerControlsLayout(),
  );

  String? _errorMessage;
  bool _isCodecError = false;
  bool _initializing = true;
  _LoadingStage _stage = _LoadingStage.loading;

  /// Set for the duration of a deliberate server change, so the loading
  /// overlay can name the mirror being switched to instead of showing the
  /// same spinner somebody was trying to escape. Cleared once the new stream
  /// is playing (or has failed).
  ServerSwitch? _serverSwitch;

  /// Which episodes are loaded and which one is playing.
  ///
  /// THE SEAM. These were three loose fields — `_episodes`, `_windowStart`,
  /// `_episodeIndex` — with the rule connecting them written in a comment and
  /// enforced by nothing. The rule is in [EpisodeWindow] now, where it is
  /// testable without a widget tree, and the sixteen tests that came with it
  /// pin the case this player got wrong for a year: Next greyed out at episode
  /// 100 of 1176, because the test asked whether the next episode was LOADED
  /// rather than whether it EXISTS.
  ///
  /// Everything below is a forwarding getter, so the hundred-odd readers
  /// spread across fifteen part files did not have to change. They can move to
  /// `_window` one at a time, or never — what matters is that there is one
  /// place left that can answer these questions wrongly.
  late EpisodeWindow _window = EpisodeWindow(
    episodes: List.of(widget.args.episodes),
    windowStart: widget.args.windowStart,
    index: 0,
    total: widget.args.effectiveTotal,
    isSerial: widget.args.isSerial,
  );

  List<EpisodeEntity> get _episodes => _window.episodes;
  int get _windowStart => _window.windowStart;
  int get _episodeIndex => _window.index;
  // Kept even though nothing reads it today: it is the question the greyed-out
  // Next button got wrong, and the next reader looking for "which episode of
  // how many" should find it here rather than adding the sum back by hand.
  // ignore: unused_element
  int get _absoluteIndex => _window.absoluteIndex;
  bool get _hasNextEpisode => _window.hasNext;
  bool get _hasPrevEpisode => _window.hasPrev;
  bool _controlsVisible = true;
  bool _locked = false;
  _SidePanel _panel = _SidePanel.none;

  String? _currentLang;
  List<String> _serverLangs = const [];

  List<SubtitleEntity> _subtitles = const [];

  /// Owned by the page, not a singleton.
  ///
  /// A cast session belongs to the thing being watched. Leaving one alive after
  /// the player closes would keep a television playing an episode the app has
  /// forgotten, with no screen left that can stop it.
  final CastController _cast = CastController();
  int _activeSubtitleIndex = -1;

  /// Cues for the active track, already sorted by start time — see
  /// [_PlayerSubtitles._loadSubtitle]. Null means "no track loaded".
  List<Caption>? _captionFile;

  /// A second subtitle track, shown above the first.
  ///
  /// For watching in a language you are learning: the original underneath, your
  /// own language above it, both timed to the same frame. Sharing one track
  /// cannot do this — the two are separate files with separate timings, and
  /// switching between them loses the line you were reading.
  List<Caption>? _secondaryCaptionFile;
  int _secondarySubtitleIndex = -1;
  // AI-translated tracks build their cues progressively and hold them here,
  // keyed by the entity's 'ai:<n>' marker, so re-selecting one restores the
  // cues instead of trying to download an empty url.
  final Map<String, List<Caption>> _aiCaptions = {};
  int _aiTrackCounter = 0;
  final ValueNotifier<int> _subtitleOffsetMs = ValueNotifier<int>(0);

  /// Frame-rate conversion factor for the active subtitle. A 25fps subtitle
  /// played over 23.976fps content drifts ~4.3%, which a constant offset cannot
  /// correct; the lookup divides by this. 1.0 means no conversion.
  final ValueNotifier<double> _subtitleRate = ValueNotifier<double>(1.0);
  SubtitleStyle _subtitleStyle = SubtitleStyle.defaults();

  String? _thumbnailsKey;
  List<_VttThumbnail> _vttThumbnails = const [];
  ThumbnailsEntity? _storyboard;
  final ValueNotifier<double?> _sliderDragValue = ValueNotifier<double?>(null);

  /// Seeded from Settings → Player in [initState]; still freely changed
  /// mid-playback from the speed sheet, which does not write the default back.
  final TitlePrefsStore _titlePrefs = TitlePrefsStore();
  final WatchStatsStore _watchStats = WatchStatsStore();

  /// Seconds already added to the totals, so a tick banks only the new stretch.
  /// Banking, the 85% mark and the once-per-episode tracker ledger.
  ///
  /// These were `_bankedSeconds`, `_trackersReported` and a threshold constant,
  /// each with a comment explaining a rule that nothing enforced. See
  /// [WatchProgress].
  final WatchProgress _progress = WatchProgress();

  /// Whether this episode has already been counted as finished. Reset when the
  /// player moves to another episode.
  bool _countedComplete = false;

  double _playbackSpeed = 1.0;

  /// The picture profile in force. Read from settings at open and changeable
  /// from the player, because the reason to change it — the room got dark — is
  /// something that happens mid-episode.
  ColorProfile _colorProfile = ColorProfile.natural;

  /// The Anime4K chain in force, and where its files live.
  ShaderPreset _shaderPreset = ShaderPreset.off;
  ShaderTier _shaderTier = ShaderTier.mid;
  final ShaderStore _shaders = ShaderStore();
  _PlayerFit _fit = _PlayerFit.contain;
  bool _isPortrait = false;
  bool _isFullscreen = false;
  double _volumeBeforeMute = 1.0;

  double _brightness = 0.5;
  double _volume = 1.0;
  final ValueNotifier<_SwipeIndicator?> _swipeIndicator =
      ValueNotifier<_SwipeIndicator?>(null);

  Offset? _dragStart;
  bool? _dragIsHorizontal;
  _SwipeType? _dragSwipeType;

  final ValueNotifier<_ScrubState?> _scrub = ValueNotifier<_ScrubState?>(null);
  final ValueNotifier<bool> _speedBoost = ValueNotifier<bool>(false);
  double? _speedBeforeBoost;

  Timer? _hideTimer;
  Timer? _historyTimer;
  late final AnimationController _controlsAnimation;

  late final AnimationController _seekRippleController;
  Timer? _seekRippleTimer;
  int _seekRippleDirection = 0;
  int _seekRippleSeconds = 0;

  int _retryAttempts = 0;

  /// Hard ceiling on auto-retries for the current episode. [_retryAttempts] is
  /// reset every time the controller reports `isInitialized`, so on a source that
  /// initializes and *then* errors (common for CloudStream links that expire or
  /// 403 mid-playback) it alone would let the retry loop run forever. This one is
  /// only cleared on a genuine fresh start (new episode / quality switch).
  int _lifetimeRetries = 0;

  bool _autoRetrying = false;
  final Stopwatch _playbackWatch = Stopwatch();
  bool _streakPingScheduled = false;

  /// Episode numbers already reported to AniList in this session.
  ///
  /// The progress check runs on every position tick, and auto-play means one
  /// player instance can cover several episodes — a plain bool would report the
  /// first episode and nothing after it.


  bool _wasPlaying = false;
  bool _wasBuffering = false;
  bool _wasInitialized = false;
  String? _lastError;

  // --- Watch2Gether (see player_page.party.dart). Fields must live here
  // because Dart extensions cannot declare instance fields.
  bool _applyingRemote = false;
  Timer? _partyHeartbeat;
  Timer? _partyDrift;
  PartyPlayback? _lastPartyPlayback;
  StreamSubscription<PartyPlayback>? _partySyncSub;
  StreamSubscription<PartyContent>? _partyContentSub;
  bool _partyControlSnapshot = false;
  // True while the sync binding (timers + stream subs) is live. Lets the player
  // activate the binding when a party is created/joined WHILE it is already open.
  bool _partyBindingActive = false;
  // Set when a party:content identity cannot be resolved on THIS device because
  // the required on-device plugin/extension is missing. Renders the actionable
  // install view in place of the generic error overlay.
  PartyResolveCapability? _pluginRequired;

  // --- Android TV / D-pad (see player_page.tv.dart). Dart extensions cannot
  // declare instance fields, so the remote's focus and step-seek state lives
  // here. All of it is inert unless isTvPlatform is true.
  //
  // _tvRootFocus is an ancestor of every control, so it sees each key before
  // the app-level directional-traversal shortcut and decides, per keystroke,
  // whether the D-pad drives playback or moves focus. It is a *scope* on
  // purpose: when a focused control is unmounted (controls auto-hide, the
  // buffering spinner replaces the play cluster) focus falls back to the
  // nearest enclosing scope. If that were the route's scope instead of this
  // node, it would no longer be in the key-event chain and the remote would go
  // dead until the next tap.
  final FocusScopeNode _tvRootFocus = FocusScopeNode(debugLabel: 'tvPlayerRoot');

  /// Focus scope for the TV side panel (quality / episodes).
  ///
  /// The panel is drawn INSIDE the player's own focus scope, so opening it did
  /// not move focus: the rows' `autofocus` only wins when nothing in the
  /// enclosing scope holds focus, and the player controls always do. The panel
  /// therefore appeared while the remote kept driving the controls behind it —
  /// which is what "quality doesn't work on TV" actually was. Giving the panel
  /// its own scope lets [_openPanel] hand focus over and [_closePanel] hand it
  /// back deterministically.
  final FocusScopeNode _tvPanelFocus =
      FocusScopeNode(debugLabel: 'tvPlayerPanel');
  final FocusNode _tvPlayFocus = FocusNode(debugLabel: 'tvPlayerPlay');
  final FocusNode _tvSeekFocus = FocusNode(debugLabel: 'tvPlayerSeek');

  /// Debounce that turns a burst of left/right presses into a single seek.
  Timer? _tvSeekCommit;
  DateTime? _tvSeekLastStep;
  int _tvSeekRepeats = 0;

  /// Side-panel scroll controller, recreated per open so the episode list can
  /// start near the episode being watched instead of at the top.
  ScrollController? _tvPanelScroll;

  /// Latched by [_exit] on TV so the intercepting [PopScope] lets the very next
  /// pop through. Without it the deliberate exit would be swallowed by the same
  /// guard that protects against accidental BACK.
  bool _tvPopAllowed = false;

  @override
  void initState() {
    super.initState();
    // Brought up alongside playback rather than at app start: on desktop it
    // opens a socket to the Discord client, and there is no reason to hold one
    // while somebody is browsing. Failure is silent and expected — Discord
    // simply may not be running.
    if (_hive.discordPresenceEnabled) {
      unawaited(getIt<DiscordPresenceService>().start());
    }
    _subtitleStyle = _hive.getSubtitleStyle();
    _playbackSpeed = _hive.getDefaultPlaybackSpeed();
    _colorProfile = ColorProfile.fromId(_hive.getColorProfile());
    _shaderPreset = ShaderPreset.fromId(_hive.getShaderPreset());
    _shaderTier = ShaderTier.fromId(_hive.getShaderTier());
    _fit = _playerFitFromId(_hive.getDefaultPlayerFit());
    _seekSeconds = _hive.getDoubleTapSeekSeconds();
    _longPressBoost = _hive.getLongPressBoost();
    _brightnessGestureEnabled = _hive.brightnessGestureEnabled;
    _volumeGestureEnabled = _hive.volumeGestureEnabled;
    _window = _window.at(
      widget.args.initialEpisodeIndex.clamp(
        0,
        _episodes.isEmpty ? 0 : _episodes.length - 1,
      ),
    );
    // Per-title first, global second. Somebody who watches one show dubbed and
    // the next subbed had a single setting fighting them on every episode; the
    // show they are actually opening now decides, and the global value is only
    // the default for a title nothing is remembered about.
    _currentLang = widget.args.initialLang ??
        _titlePrefs.langFor(widget.args.provider, widget.args.contentUrl ?? '') ??
        _hive.getPreferredMediaLang();
    _restoreSubtitleSync();
    _controlsAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1,
    );
    _seekRippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    WidgetsBinding.instance.addObserver(this);
    _pipChannel.setMethodCallHandler(_onPipMethodCall);
    unawaited(_loadSystemControlValues());
    PlayerLog.instance
      ..clear()
      ..clearContext()
      ..setContext({
        'provider': widget.args.provider,
        'title': widget.args.title,
        'serial': widget.args.isSerial.toString(),
      });
    unawaited(PlayerLog.instance.init());
    if (isTvPlatform) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tvRootFocus.requestFocus();
      });
    }
    _partyInit();
    _startup();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null) return;
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (!isDesktopPlatform &&
            c.value.isInitialized &&
            c.value.isPlaying &&
            !_isPip) {
          _resumeAfterPause = true;
          c.pause();
        }
        break;
      case AppLifecycleState.resumed:
        if (_isPip && mounted) {
          setState(() => _isPip = false);
        }
        if (_resumeAfterPause && c.value.isInitialized) {
          c.play();
        }
        _resumeAfterPause = false;
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  void _plog(String message, {LogLevel level = LogLevel.info}) =>
      PlayerLog.instance.add(message, level: level);

  @override
  void dispose() {
    // Discord first, and unconditionally.
    //
    // Leaving a profile saying somebody is watching a film they closed an hour
    // ago is the one failure of this feature that other people can see, so it
    // is cleared before anything below is allowed to throw. Cheap when
    // presence was never switched on: the service is inert until started.
    if (_hive.discordPresenceEnabled) {
      final discord = getIt<DiscordPresenceService>();
      discord.update(null);
      unawaited(discord.stop());
    }

    // A television left playing an episode the app has forgotten has no screen
    // left that can stop it, so the session goes before anything else can throw
    // and skip this.
    _cast.dispose();
    // Then stop seeding. Fire-and-forget because dispose cannot await, and the
    // request is a localhost round trip that completes long before the process
    // would care.
    final torrentHash = _torrentHash;
    if (torrentHash != null) {
      _torrentEngine.drop(torrentHash).whenComplete(_torrentEngine.dispose);
      _torrentHash = null;
    } else {
      _torrentEngine.dispose();
    }
    _saveHistory();
    // Push the position the viewer just stopped at, so another device can pick
    // it up. Without this the progress only leaves the phone the next time the
    // History screen happens to be opened.
    getIt<HistorySyncService>().sync();
    _partyDispose();
    WidgetsBinding.instance.removeObserver(this);
    _pipChannel.setMethodCallHandler(null);
    _sleepTicker?.cancel();
    _hideTimer?.cancel();
    _historyTimer?.cancel();
    _seekRippleTimer?.cancel();
    _tvSeekCommit?.cancel();
    _tvRootFocus.dispose();
    _tvPanelFocus.dispose();
    _tvPlayFocus.dispose();
    _tvSeekFocus.dispose();
    _tvPanelScroll?.dispose();
    _controlsAnimation.dispose();
    _seekRippleController.dispose();
    _scrub.dispose();
    _speedBoost.dispose();
    _swipeIndicator.dispose();
    _sliderDragValue.dispose();
    _subtitleOffsetMs.dispose();
    _subtitleRate.dispose();
    final c = _controller;
    if (c != null) {
      c.removeListener(_onMajorChange);
      try {
        c.pause();
      } catch (_) {}
      c.dispose();
    }
    _controller = null;
    FramePreviewService.close();
    _restoreSystemUi();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // BACK is the *only* dismiss affordance on a remote, so on TV the player
      // intercepts it and unwinds one layer at a time (panel -> pending scrub ->
      // controls -> exit) rather than dumping the viewer out mid-episode.
      // _exit() latches _tvPopAllowed when the exit is genuinely intended.
      // Phone and desktop keep the unconditional pop they ship today.
      canPop: !isTvPlatform || _tvPopAllowed,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !isTvPlatform) {
          _restoreSystemUi();
          return;
        }
        _onTvBack();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: _wrapPlayerShortcuts(
          Scaffold(
          backgroundColor: Colors.black,
          body: LayoutBuilder(
            builder: (context, constraints) => _wrapHover(GestureDetector(
              // ANCESTOR of the whole Stack, deliberately, and it has to stay
              // that way.
              //
              // It was briefly moved to a Positioned.fill sibling below the
              // controls, to stop its long-press recogniser competing with the
              // seek bar's drag. That broke two things and fixed nothing worth
              // the trade. Measured, not guessed:
              //
              //  * The controls scrim is a full-screen DecoratedBox, and a
              //    RenderDecoratedBox DOES take the hit — a hit-test at the
              //    centre of the screen stops there and never reaches a sibling
              //    below it. So every gesture died the moment the controls
              //    became visible, which is exactly how it was reported.
              //  * The error card, the missing-plugin view and the loading
              //    overlay all live in the Stack's first child, so an opaque
              //    sibling above them swallowed Try again, Alternate sources
              //    and View logs.
              //  * And the conflict it was meant to fix does not cancel the
              //    drag at all: holding the thumb past the long-press timeout
              //    still delivers onChangeEnd. It only fires a spurious 2x
              //    speed boost, which _absorbAncestorGestures now stops at the
              //    seek bar itself.
              //
              // As an ancestor these recognisers are in the hit-test path for
              // every touch, whatever is drawn on top.
              behavior: HitTestBehavior.opaque,
              onTap: _locked ? null : _toggleControls,
              onDoubleTapDown: _locked || isDesktopPlatform
                  ? null
                  : (d) => _onDoubleTapDown(d, constraints),
              onDoubleTap: _locked
                  ? null
                  : isDesktopPlatform
                      ? _toggleFullscreen
                      : () {},
              // Scale, not pan: Flutter asserts if both are registered, since
              // scale is a superset. One finger is routed straight back into
              // the old pan handlers — see _onScaleUpdate — so brightness,
              // volume and swipe-seek behave exactly as before, and two
              // fingers pinch-zoom the picture.
              onScaleStart:
                  _locked ? null : (d) => _onScaleStart(d, constraints),
              onScaleUpdate:
                  _locked ? null : (d) => _onScaleUpdate(d, constraints),
              onScaleEnd: _locked ? null : _onScaleEnd,
              onLongPressStart: _locked ? null : _onLongPressStart,
              onLongPressEnd: _locked ? null : _onLongPressEnd,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildVideoLayer(),
                  _buildSubtitleOverlay(),
                  if (!_locked) _buildSeekRipple(),
                  if (_locked) _buildLockOverlay() else _buildControlsOverlay(),
                  if (!_locked) _buildScrubOverlay(),
                  if (!_locked) _buildSpeedBoostBadge(),
                  if (!_locked) _buildSwipeIndicator(),
                  // Renders nothing unless the URL is a local torrent stream,
                  // so it is safe to hand it every playback unconditionally.
                  // It keeps showing while the controls are hidden if the
                  // pre-buffer is still filling — that is precisely when the
                  // picture is frozen and the user needs to know why.
                  TorrentStatsOverlay(
                    videoUrl: _videoUrl,
                    visible: _controlsVisible && !_locked,
                  ),
                  // Above the controls layer so it is reachable while they are
                  // hidden — the offer is at its most useful to a viewer who has
                  // not touched the screen. Renders nothing when no interval is
                  // active, so it costs nothing on non-anime playback.
                  if (!_locked) _buildPlayerInfoOverlay(),
                  if (!_locked) _buildSkipButton(),
                  if (!_locked && _panel != _SidePanel.none) _buildSidePanel(),
                  if (!_locked && _inParty) _buildPartyReactionsLayer(),
                  // Last, so it covers everything: while a television is
                  // playing this episode the phone is a remote, and leaving the
                  // local controls reachable underneath would let someone
                  // scrub a surface nobody is watching.
                  _buildCastOverlay(),
                ],
              ),
            )),
          ),
        )),
      ),
    );
  }

  Widget _wrapPlayerShortcuts(Widget child) {
    if (isTvPlatform) {
      // Separate handler, not a widened gate: the desktop map consumes all four
      // arrows unconditionally, which on a remote would make directional focus
      // traversal impossible. See player_page.tv.dart.
      // Focus is claimed from initState rather than via autofocus: the error
      // overlay's retry button also autofocuses, and two autofocus requests
      // resolved in one frame within the same scope trip a debug assertion.
      return FocusScope(
        node: _tvRootFocus,
        onKeyEvent: _onTvPlayerKey,
        child: child,
      );
    }
    if (!isDesktopPlatform) return child;
    return Focus(autofocus: true, onKeyEvent: _onPlayerKey, child: child);
  }

  Widget _wrapHover(Widget child) {
    if (!isDesktopPlatform) return child;
    return MouseRegion(
      onHover: (_) => _revealControlsForHover(),
      cursor: _controlsVisible ? MouseCursor.defer : SystemMouseCursors.none,
      child: child,
    );
  }

  void _revealControlsForHover() {
    if (_locked || _isPip) return;
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
      _controlsAnimation.forward();
    }
    _scheduleHide();
  }

  KeyEventResult _onPlayerKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    // Block playback-control keys (play/pause + seek) when not allowed to
    // control the party; consume the event so no local action happens.
    final isPartyControlKey = k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.mediaPlayPause ||
        k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowRight;
    if (isPartyControlKey && _partyBlockLocal()) {
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.mediaPlayPause) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      _seekRelative(-_seekStep);
      _showSeekRipple(-1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      _seekRelative(_seekStep);
      _showSeekRipple(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      _setPlayerVolume(_volume + 0.1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      _setPlayerVolume(_volume - 0.1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyM) {
      _toggleMute();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      if (_panel != _SidePanel.none) {
        _closePanel();
      } else if (_isFullscreen) {
        _toggleFullscreen();
      } else {
        _exit();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}
