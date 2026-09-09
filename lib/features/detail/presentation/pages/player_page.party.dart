// ignore_for_file: invalid_use_of_protected_member
part of 'player_page.dart';

/// Watch2Gether integration for the player.
///
/// Fields (`_applyingRemote`, the two timers, the two subscriptions,
/// `_lastPartyPlayback`, `_partyControlSnapshot`) live in `_PlayerPageState`
/// (player_page.dart) because Dart extensions cannot declare instance fields.
///
/// Invariants:
///  * A resolved stream URL is NEVER put on the wire — only identity fields.
///  * `_applyingRemote` guards against the sync feedback loop: while it is true
///    no `party:control` is emitted, so applying a remote sync never echoes back.
///  * Guests never self-advance episodes and never resolve peer URLs — every
///    device resolves its own stream from identity via [ResolveMediaUseCase].
extension _PlayerParty on _PlayerPageState {
  WatchPartyService get _party => getIt<WatchPartyService>();
  PartyState get _partyState => _party.state.value;
  bool get _inParty => _partyState.inParty;
  bool get _isPartyHost => _partyState.isHost;
  bool get _canPartyControl => _partyState.canControl;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  void _partyInit() {
    _party.state.addListener(_onPartyStateChanged);
    _syncPartyBinding();
  }

  void _partyDispose() {
    _party.state.removeListener(_onPartyStateChanged);
    _stopPartyBinding();
  }

  /// Starts the sync binding when in a party — including the case where the
  /// party is created/joined WHILE this player is already open — and tears it
  /// down when the party ends.
  void _syncPartyBinding() {
    if (_inParty && !_partyBindingActive) {
      _startPartyBinding();
    } else if (!_inParty && _partyBindingActive) {
      _stopPartyBinding();
    }
  }

  void _startPartyBinding() {
    _partyBindingActive = true;
    _partyControlSnapshot = _canPartyControl;
    // Seed the guest's drift target from the room snapshot so the first drift
    // correction can happen before the first `party:sync` arrives.
    final snapshot = _partyState.room?.playback;
    if (!_isPartyHost && snapshot != null) {
      _lastPartyPlayback = snapshot;
    }
    _partySyncSub = _party.syncs.listen(_onPartySync);
    _partyContentSub = _party.contentChanges.listen(_onPartyContent);
    // Both timers run and self-guard by role, so host migration is handled
    // without tearing anything down.
    _partyHeartbeat = Timer.periodic(
      PartyRules.heartbeatPeriod,
      (_) => _onHeartbeatTick(),
    );
    _partyDrift = Timer.periodic(
      PartyRules.driftPeriod,
      (_) => _onDriftTick(),
    );
    // As host, announce what this player is showing so guests can resolve it on
    // their own device (covers "create a party while already watching").
    if (_isPartyHost) _partyEmitCurrentContent();
  }

  void _stopPartyBinding() {
    _partyBindingActive = false;
    _partyHeartbeat?.cancel();
    _partyHeartbeat = null;
    _partyDrift?.cancel();
    _partyDrift = null;
    unawaited(_partySyncSub?.cancel());
    _partySyncSub = null;
    unawaited(_partyContentSub?.cancel());
    _partyContentSub = null;
  }

  // ---------------------------------------------------------------------------
  // Incoming events
  // ---------------------------------------------------------------------------

  void _onPartyStateChanged() {
    if (!mounted) return;
    final wasActive = _partyBindingActive;
    _syncPartyBinding(); // may flip _partyBindingActive on join/leave
    // Rebuild ONLY on visible transitions (join/leave or host migration) — never
    // on the frequent playback syncs, which also fire this notifier.
    final canControl = _canPartyControl;
    if (PartyRules.needsRepaint(
      wasBound: wasActive,
      isBound: _partyBindingActive,
      hadControl: _partyControlSnapshot,
      hasControl: canControl,
    )) {
      _partyControlSnapshot = canControl;
      setState(() {});
    }
  }

  // ---------------------------------------------------------------------------
  // Entry point (top-bar "Watch together" button)
  // ---------------------------------------------------------------------------

  /// Identity of what this player is currently showing. Never a stream URL —
  /// each device resolves its own from this. For a serial it is the current
  /// episode; for a movie it is the retained args mediaRef.
  PartyContent _currentPartyContent() {
    final eps = _episodes;
    final ep =
        (eps.isNotEmpty && _episodeIndex >= 0 && _episodeIndex < eps.length)
        ? eps[_episodeIndex]
        : null;
    return PartyContent(
      provider: widget.args.provider,
      contentUrl: widget.args.contentUrl,
      mediaRef: ep?.mediaRef ?? widget.args.mediaRef,
      title: widget.args.title,
      thumbnail: widget.args.thumbnail,
      episode: ep?.episode,
      lang: _currentLang ?? widget.args.lang,
    );
  }

  void _partyEmitCurrentContent() {
    final c = _currentPartyContent();
    if (c.mediaRef != null && c.mediaRef!.isNotEmpty) {
      _party.sendContent(c);
    }
  }

  /// Top-bar action: open the lobby if already in a party, otherwise create one
  /// for the current content (the binding then activates via the state listener).
  Future<void> _openWatchParty() async {
    if (_inParty) {
      final code = _partyState.code;
      if (code != null) {
        context.push('/watch-party', extra: WatchPartyArgs(code: code));
      }
      return;
    }
    final content = _currentPartyContent();
    if (content.mediaRef == null || content.mediaRef!.isEmpty) {
      _partyToast('watch_party.not_available');
      return;
    }
    await showCreatePartySheet(context, content: content);
  }

  // ---------------------------------------------------------------------------
  // In-player reactions overlay (chat + host controls live in the lobby)
  // ---------------------------------------------------------------------------

  /// Full-bleed, non-interactive layer that floats reactions up over the video.
  Widget _buildPartyReactionsLayer() {
    return Positioned.fill(child: PartyReactionsOverlay(service: _party));
  }

  bool get _followsParty =>
      PartyRules.followsRemote(inParty: _inParty, isHost: _isPartyHost);

  void _onPartySync(PartyPlayback pb) {
    _lastPartyPlayback = pb;
    if (_followsParty) unawaited(_applyRemoteSync(pb));
  }

  void _onPartyContent(PartyContent content) {
    if (_followsParty) unawaited(_applyRemoteContent(content));
  }

  void _onHeartbeatTick() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (PartyRules.sendsHeartbeat(
      inParty: _inParty,
      isHost: _isPartyHost,
      isLive: _isLive,
    )) {
      _party.sendHeartbeat(c.value.position.inMilliseconds / 1000.0);
    }
  }

  void _onDriftTick() {
    final pb = _lastPartyPlayback;
    if (pb != null && _followsParty) unawaited(_applyRemoteSync(pb));
  }

  // ---------------------------------------------------------------------------
  // Control-surface gates
  // ---------------------------------------------------------------------------

  /// Blocks a local play/pause/seek/rate action (and toasts) when this device
  /// is in a party but not allowed to control it. Never blocks while a remote
  /// sync is being applied.
  bool _partyBlockLocal() {
    if (PartyRules.blocksLocalControl(
      inParty: _inParty,
      canControl: _canPartyControl,
      applyingRemote: _applyingRemote,
    )) {
      _partyToast('watch_party.only_host_controls');
      return true;
    }
    return false;
  }

  /// Episode navigation changes *what* is being watched, so it is host-only —
  /// even for a guest that would otherwise be allowed to control playback.
  bool _partyBlockEpisodeNav() {
    if (PartyRules.blocksEpisodeNav(
      inParty: _inParty,
      isHost: _isPartyHost,
      applyingRemote: _applyingRemote,
    )) {
      _partyToast('watch_party.only_host_controls');
      return true;
    }
    return false;
  }

  void _partyEpisodeNav(int index) {
    if (_partyBlockEpisodeNav()) return;
    _loadEpisode(index);
  }

  /// Emits a `party:control` — no-op unless we are in a party, allowed to
  /// control it, and not mid-apply of a remote sync (the feedback-loop guard).
  void _partyEmit(String action, {double? positionSec, double? rate}) {
    if (!PartyRules.emitsControl(
      inParty: _inParty,
      canControl: _canPartyControl,
      applyingRemote: _applyingRemote,
    )) {
      return;
    }
    _party.sendControl(action: action, positionSec: positionSec, rate: rate);
  }

  /// Host announces the identity of the episode it just loaded. Never carries a
  /// resolved video URL — the server would strip it anyway, and each guest
  /// resolves its own stream. No `season`/`server` exist in this app.
  void _partyEmitContent(EpisodeEntity ep, String? lang) {
    if (!_inParty || !_isPartyHost) return;
    _party.sendContent(
      PartyContent(
        provider: widget.args.provider,
        contentUrl: widget.args.contentUrl,
        mediaRef: ep.mediaRef,
        title: widget.args.title,
        thumbnail: widget.args.thumbnail,
        episode: ep.episode,
        lang: lang,
      ),
    );
  }

  void _partyToast(String key) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(key.tr()),
        backgroundColor: Colors.black87,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Applying remote state
  // ---------------------------------------------------------------------------

  Future<void> _applyRemoteSync(PartyPlayback pb) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (_isLive) return; // live streams are unseekable
    if (_applyingRemote) return; // avoid overlapping applies
    _applyingRemote = true;
    try {
      final expected = pb.expectedPositionAt(DateTime.now());
      final actual = c.value.position.inMilliseconds / 1000.0;
      if (PartyRules.needsSeek(actual, expected)) {
        await c.seekTo(Duration(milliseconds: (expected * 1000).round()));
      }
      if (PartyRules.needsRateChange(_playbackSpeed, pb.rate)) {
        // setState, not a bare assignment: the bottom bar prints _playbackSpeed
        // as the Speed button's label. Without a rebuild the host could put the
        // room on 2x and every guest's engine would follow while their button
        // went on saying 1x — and the next tap would then offer to "change" to
        // the speed already playing.
        setState(() => _playbackSpeed = pb.rate);
        await c.setPlaybackSpeed(pb.rate);
      }
      switch (PartyRules.transportFor(
        remoteIsPlaying: pb.isPlaying,
        localIsPlaying: c.value.isPlaying,
      )) {
        case PartyTransport.play:
          await c.play();
        case PartyTransport.pause:
          await c.pause();
        case PartyTransport.leave:
          break;
      }
    } finally {
      _applyingRemote = false;
    }
  }

  /// Guest side: a new content identity arrived. Re-resolve the stream ON THIS
  /// DEVICE (never reuse a peer's URL), then start playback aligned to the
  /// party's current position/rate.
  Future<void> _applyRemoteContent(PartyContent content) async {
    final ref = content.mediaRef;
    final provider = content.provider;
    if (ref == null || ref.isEmpty || provider == null || provider.isEmpty) {
      return;
    }

    final cap = await PartyResolveGate.canResolve(provider);
    if (!mounted) return;
    if (!cap.ok) {
      // This device cannot resolve the provider (missing plugin/extension).
      // Stop the old stream (otherwise its audio keeps playing behind the
      // overlay and the drift timer keeps driving it) and surface the same
      // actionable install view the lobby uses instead of a generic error with
      // a misleading "Try again" that would reload the previous title.
      await _disposeController();
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _errorMessage = null;
        _isCodecError = false;
        _panel = _SidePanel.none;
        _pluginRequired = cap;
      });
      return;
    }

    setState(() {
      _initializing = true;
      _stage = _LoadingStage.resolving;
      _errorMessage = null;
      _isCodecError = false;
      _pluginRequired = null;
      _panel = _SidePanel.none;
    });
    await _disposeController();
    if (!mounted) return;

    final result = await _resolve(
      ref: ref,
      provider: provider,
      lang: content.lang,
    );
    if (!mounted) return;

    switch (result) {
      case Success(:final value):
        final sources = value.videoSources;
        // A guest took `sources[0]`, so a party could be watching an embed
        // page while the host watched the stream. Same ladder as everywhere.
        _resetLadder();
        final pickedIdx = _ladder(
              sources,
              hasDirective: value.extractor != null,
            ).initialPick() ??
            -1;
        final useSources = pickedIdx >= 0;
        final url = useSources ? sources[pickedIdx].videoUrl : value.videoUrl;
        setState(() {
          _stage = _LoadingStage.loading;
          _serverLangs = value.languagesAvailable;
          _currentLang = content.lang ?? value.activeLang ?? _currentLang;
          _videoSources = useSources ? List.of(sources) : const [];
          _currentSourceIndex = pickedIdx;
          _currentQuality = useSources ? sources[pickedIdx].quality : null;
          // The ladder above was told a directive exists; _initializeWith
          // reads THIS to decide whether to sniff. Leaving it stale meant the
          // pick assumed a sniff that never ran, and an embed page went
          // straight to the decoder.
          _extractorConfig = value.extractor;
          _subtitles = value.subtitles;
          _activeSubtitleIndex = -1;
          _captionFile = null;
          // The title changed under the guest; the old one's second track
          // would otherwise keep rendering over the new video.
          _secondarySubtitleIndex = -1;
          _secondaryCaptionFile = null;
        });
        unawaited(_loadThumbnails(value.thumbnails));
        await _initializeWith(
          url: url,
          headers: value.headers,
          type: value.type,
          party: _lastPartyPlayback,
        );
        final subs = value.subtitles;
        if (subs.isNotEmpty) {
          final defaultIdx = subs.indexWhere((s) => s.isDefault);
          if (defaultIdx >= 0) _loadSubtitle(defaultIdx);
        }
      case Failure(:final error):
        setState(() {
          _initializing = false;
          _errorMessage = error.toString().replaceFirst('Exception: ', '');
        });
    }
  }
}
