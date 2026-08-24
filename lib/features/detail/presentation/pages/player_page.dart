import 'package:soplay/core/network/user_agent.dart';
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:floating/floating.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/diagnostics/log_viewer_sheet.dart';
import 'package:soplay/core/diagnostics/player_log.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/player/external_player.dart';
import 'package:soplay/core/player/local_hls_proxy.dart';
import 'package:soplay/core/player/player_engine.dart';
import 'package:soplay/core/player/webview_stream_extractor.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/app_orientation.dart';
import 'package:soplay/core/system/desktop_window.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/anilist/data/anilist_tracker.dart';
import 'package:soplay/features/mal/data/mal_tracker.dart';
import 'package:soplay/features/cloudflare/cloudflare_solver.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
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
import 'package:soplay/features/detail/presentation/widgets/player_engine_sheet.dart';
import 'package:soplay/features/detail/domain/usecases/resolve_media_usecase.dart';
import 'package:soplay/features/streak/data/streak_service.dart';
import 'package:soplay/features/streak/presentation/dialogs/streak_milestone_dialog.dart';
import 'package:soplay/features/download/data/download_service.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
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

part 'player_page.models.dart';
part 'player_page.widgets.dart';
part 'player_page.media.dart';
part 'player_page.controls.dart';
part 'player_page.panels.dart';
part 'player_page.subtitles.dart';
part 'player_page.gestures.dart';
part 'player_page.history.dart';
part 'player_page.pip.dart';
part 'player_page.party.dart';
part 'player_page.tv.dart';

/// Hard ceiling on auto-retries per episode — see [_PlayerPageState._lifetimeRetries].
const int _kMaxLifetimeRetries = 4;

/// Reconnect budget for a live broadcast, which is a different problem.
///
/// A film either plays or is broken, so four attempts in a session is generous.
/// A channel drops — a segment gap, a CDN failing over, a phone changing
/// network — and the only correct response is to reconnect and keep watching.
/// Four in a two-hour evening meant the player gave up permanently on something
/// that was working again seconds later.
const int _kMaxLiveRetries = 1000;

/// How long to wait before reconnecting a dropped channel, by attempt.
///
/// Fast enough that a blip is invisible, and backing off so a channel that is
/// genuinely off air is not hammered all evening.
Duration _liveRetryBackoff(int attempt) {
  const steps = [1, 2, 4, 8, 15];
  return Duration(seconds: steps[attempt < steps.length ? attempt : steps.length - 1]);
}

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
  final DownloadService _downloads = getIt<DownloadService>();
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

  bool _isPip = false;
  bool _resumeAfterPause = false;
  bool _lastPipPlaying = false;

  PlayerController? _controller;
  late int _episodeIndex;
  String? _currentQuality;
  String? _videoUrl;
  String? _mediaType;
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
  bool _autoFallbackUsed = false;
  String? _errorMessage;
  bool _isCodecError = false;
  bool _initializing = true;
  _LoadingStage _stage = _LoadingStage.loading;
  bool _controlsVisible = true;
  bool _locked = false;
  _SidePanel _panel = _SidePanel.none;

  String? _currentLang;
  List<String> _serverLangs = const [];

  List<SubtitleEntity> _subtitles = const [];
  int _activeSubtitleIndex = -1;

  /// Cues for the active track, already sorted by start time — see
  /// [_PlayerSubtitles._loadSubtitle]. Null means "no track loaded".
  List<Caption>? _captionFile;
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
  double _playbackSpeed = 1.0;
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
  final Set<int> _trackersReported = <int>{};

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
    _subtitleStyle = _hive.getSubtitleStyle();
    _playbackSpeed = _hive.getDefaultPlaybackSpeed();
    _fit = _playerFitFromId(_hive.getDefaultPlayerFit());
    _seekSeconds = _hive.getDoubleTapSeekSeconds();
    _longPressBoost = _hive.getLongPressBoost();
    _brightnessGestureEnabled = _hive.brightnessGestureEnabled;
    _volumeGestureEnabled = _hive.volumeGestureEnabled;
    _episodeIndex = widget.args.initialEpisodeIndex.clamp(
      0,
      widget.args.episodes.isEmpty ? 0 : widget.args.episodes.length - 1,
    );
    _currentLang = widget.args.initialLang ?? _hive.getPreferredMediaLang();
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
    _saveHistory();
    // Push the position the viewer just stopped at, so another device can pick
    // it up. Without this the progress only leaves the phone the next time the
    // History screen happens to be opened.
    getIt<HistorySyncService>().sync();
    _partyDispose();
    WidgetsBinding.instance.removeObserver(this);
    _pipChannel.setMethodCallHandler(null);
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
              onPanStart: _locked ? null : (d) => _onPanStart(d, constraints),
              onPanUpdate: _locked ? null : (d) => _onPanUpdate(d, constraints),
              onPanEnd: _locked ? null : _onPanEnd,
              onPanCancel: _locked ? null : _onPanCancel,
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
                  if (!_locked && _panel != _SidePanel.none) _buildSidePanel(),
                  if (!_locked && _inParty) _buildPartyReactionsLayer(),
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
