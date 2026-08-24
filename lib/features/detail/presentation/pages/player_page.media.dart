// ignore_for_file: invalid_use_of_protected_member
part of 'player_page.dart';

extension _PlayerMedia on _PlayerPageState {
  String? _defaultRefererFor(String provider) {
    switch (provider.toLowerCase()) {
      case 'asilmedia':
        return 'https://asilmedia.org/';
      default:
        return null;
    }
  }

  bool _isHlsType(String? type) => type?.trim().toLowerCase() == 'hls';

  Future<void> _bootstrap() async {
    final resume = widget.args.resumePosition;
    if (widget.args.isSerial) {
      await _loadEpisode(_episodeIndex, resumeAt: resume);
    } else {
      _videoSources = List.of(widget.args.videoSources);
      _currentSourceIndex = _pickInitialMovieSourceIndex(_videoSources);
      _autoFallbackUsed = false;
      final source = _currentSourceIndex >= 0
          ? _videoSources[_currentSourceIndex]
          : null;
      _currentQuality = source?.quality;
      if (mounted) setState(() => _stage = _LoadingStage.loading);
      unawaited(_loadThumbnails(widget.args.thumbnails));
      await _initializeWith(
        url: source?.videoUrl ?? widget.args.movieUrl ?? '',
        headers: widget.args.headers,
        type: widget.args.type,
        resumeAt: resume,
      );
    }
  }

  int _pickInitialMovieSourceIndex(List<VideoSourceEntity> sources) {
    if (sources.isEmpty) return -1;
    for (var i = 0; i < sources.length; i++) {
      if (sources[i].isDefault && sources[i].accessible) return i;
    }
    for (var i = 0; i < sources.length; i++) {
      if (sources[i].accessible) return i;
    }
    return 0;
  }

  Future<void> _loadEpisode(
    int index, {
    Duration resumeAt = Duration.zero,
    bool keepRetryCount = false,
  }) async {
    if (index < 0 || index >= widget.args.episodes.length) return;
    if (!keepRetryCount) {
      _retryAttempts = 0;
      _lifetimeRetries = 0;
    }
    setState(() {
      _initializing = true;
      _stage = _LoadingStage.resolving;
      _errorMessage = null;
      _isCodecError = false;
      _episodeIndex = index;
      _panel = _SidePanel.none;
    });
    // Sync is per-episode: a shift/rate tuned for the previous episode is wrong
    // here, so drop it and load whatever was saved for this one (0 / 1.0 when
    // nothing was).
    _restoreSubtitleSync();
    await _disposeController();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    final ep = widget.args.episodes[index];
    if (ep.mediaRef.isEmpty) {
      setState(() {
        _initializing = false;
        _errorMessage = 'No source for this episode';
      });
      return;
    }

    final lang = _resolveLangForEpisode(ep);

    final resolveSw = Stopwatch()..start();
    final provider = widget.args.provider;
    _plog('resolving ref=${ep.mediaRef} lang=$lang');
    final result = await _resolve(
      ref: ep.mediaRef,
      provider: provider,
      lang: lang,
    );
    _plog('resolve completed in ${resolveSw.elapsedMilliseconds}ms');
    if (!mounted) return;

    switch (result) {
      case Success(:final value):
        final sources = value.videoSources;
        final useSources = sources.isNotEmpty;
        final pickedIdx = useSources ? 0 : -1;
        final url = useSources ? sources[pickedIdx].videoUrl : value.videoUrl;
        final subs = value.subtitles;
        setState(() {
          _stage = _LoadingStage.loading;
          _serverLangs = value.languagesAvailable;
          _currentLang = lang ?? value.activeLang ?? _currentLang;
          _videoSources = useSources ? List.of(sources) : const [];
          _currentSourceIndex = pickedIdx;
          _currentQuality = useSources ? sources[pickedIdx].quality : null;
          _autoFallbackUsed = false;
          _subtitles = subs;
          _activeSubtitleIndex = -1;
          _captionFile = null;
          _extractorConfig = value.extractor;
        });
        unawaited(_loadThumbnails(value.thumbnails));
        await _initializeWith(
          url: url,
          headers: value.headers,
          type: value.type,
          resumeAt: resumeAt,
        );
        // Host announces the new episode identity (never a video URL).
        if (_errorMessage == null) _partyEmitContent(ep, _currentLang);
        if (subs.isNotEmpty) {
          final defaultIdx = subs.indexWhere((s) => s.isDefault);
          if (defaultIdx >= 0) {
            unawaited(_loadSubtitle(defaultIdx));
          }
        }
      case Failure(:final error):
        setState(() {
          _initializing = false;
          _errorMessage = error.toString().replaceFirst('Exception: ', '');
        });
    }
  }

  String? _resolveLangForEpisode(EpisodeEntity ep) {
    final epLangs = ep.availableLangs;
    if (epLangs.isEmpty) return null;
    final saved = _currentLang;
    if (saved != null && epLangs.contains(saved)) return saved;
    if (epLangs.contains(_kSubLang)) return _kSubLang;
    return epLangs.first;
  }

  List<String> _availableLangsForCurrentEpisode() {
    if (!widget.args.isSerial) return const [];
    if (_episodeIndex < 0 || _episodeIndex >= widget.args.episodes.length) {
      return const [];
    }
    final epLangs = widget.args.episodes[_episodeIndex].availableLangs;
    if (epLangs.isNotEmpty) return epLangs;
    return _serverLangs;
  }

  Future<void> _switchLang(String lang) async {
    if (!widget.args.isSerial) return;
    if (lang == _currentLang) return;
    final keepPosition = _controller?.value.position ?? Duration.zero;
    setState(() => _currentLang = lang);
    await _hive.savePreferredMediaLang(lang);
    await _loadEpisode(_episodeIndex, resumeAt: keepPosition);
  }

  Future<void> _switchQuality(VideoSourceEntity source) async {
    if (source.quality == _currentQuality) {
      setState(() => _panel = _SidePanel.none);
      return;
    }
    final keepPosition = _controller?.value.position ?? Duration.zero;
    final idx = _videoSources.indexWhere((s) => s.quality == source.quality);
    _retryAttempts = 0;
    _lifetimeRetries = 0;
    setState(() {
      _initializing = true;
      _stage = _LoadingStage.loading;
      _errorMessage = null;
      _isCodecError = false;
      _currentQuality = source.quality;
      _currentSourceIndex = idx >= 0 ? idx : _currentSourceIndex;
      _autoFallbackUsed = false;
      _panel = _SidePanel.none;
    });
    await _disposeController();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    await _initializeWith(
      url: source.videoUrl,
      headers: _headers.isNotEmpty ? _headers : widget.args.headers,
      type: _mediaType,
      resumeAt: keepPosition,
    );
  }

  Future<_ProxiedTarget?> _maybeRouteThroughLocalProxy({
    required String url,
    required Map<String, String> headers,
  }) async {
    if (_currentSourceIndex < 0 ||
        _currentSourceIndex >= _videoSources.length) {
      _plog(
        'local proxy skipped: no current source '
        '(idx=$_currentSourceIndex, count=${_videoSources.length}) — direct URL',
        level: LogLevel.warn,
      );
      return null;
    }
    final source = _videoSources[_currentSourceIndex];
    if (!source.useLocalProxy) {
      // If this fires for a uzmovi source, the backend flag or the
      // localProxy/requestTransform maps were dropped somewhere between resolve
      // and here — the player then hits the protected CDN directly and fails.
      _plog(
        'local proxy skipped: useLocalProxy=false '
        '(transform=${source.requestTransform.isNotEmpty}, '
        'localProxy=${source.localProxy.isNotEmpty}) — direct URL',
        level: LogLevel.warn,
      );
      return null;
    }
    if (source.videoUrl != url) {
      _plog(
        'local proxy skipped: url mismatch — direct URL\n'
        '  source.videoUrl=${source.videoUrl}\n'
        '  play url       =$url',
        level: LogLevel.warn,
      );
      return null;
    }
    final upstreamHeaders = source.headers.isNotEmpty ? source.headers : headers;
    try {
      final proxied = await getIt<LocalHlsProxy>().register(
        upstreamUrl: url,
        headers: upstreamHeaders,
        localProxy: source.localProxy,
        requestTransform: source.requestTransform,
      );
      _plog('routing through local HLS proxy: $proxied');
      return _ProxiedTarget(url: proxied, headers: const {});
    } catch (e) {
      _plog('local proxy register failed: $e — using direct url',
          level: LogLevel.warn);
      return null;
    }
  }

  /// Swap a sniffed url for the one the server says is worth playing.
  ///
  /// Players that request a single rendition leave the sniffer holding one
  /// fixed quality while the master — and with it the whole ladder — sits under
  /// a derivable name. The rule comes from the server so the app never learns
  /// which site it is talking to.
  ///
  /// A derived url is a guess about someone else's naming, so it is fetched
  /// before it is trusted: anything that is not a playlist leaves the sniffed
  /// url in place. One request, and only when a rule was sent at all.
  Future<String> _applyRewrite(
    UrlRewrite? rule,
    String url,
    Map<String, String> headers,
  ) async {
    if (rule == null) return url;
    final candidate = rule.apply(url);
    if (candidate == null) return url;
    if (!rule.verify) {
      _plog('rewrite (unverified) -> $candidate');
      return candidate;
    }
    try {
      final res = await getIt<Dio>().get<String>(
        candidate,
        options: Options(
          headers: headers,
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
          receiveTimeout: const Duration(seconds: 10),
          extra: const {'skipAuthInterceptor': true},
        ),
      );
      final body = res.data ?? '';
      if (res.statusCode == 200 && body.trimLeft().startsWith('#EXTM3U')) {
        _plog('rewrite ok -> $candidate');
        return candidate;
      }
      _plog(
        'rewrite rejected (${res.statusCode}) — playing the sniffed url',
        level: LogLevel.warn,
      );
    } catch (e) {
      _plog('rewrite check failed: $e — playing the sniffed url',
          level: LogLevel.warn);
    }
    return url;
  }

  /// Entry point for every playback start. Resolves a page-url source to its
  /// real manifest first, then hands off to [_initializeResolved].
  ///
  /// A wrapper rather than an inline block because all eight call sites (first
  /// play, episode change, quality switch, party sync, retry, fallback) must go
  /// through the sniff — putting it here means none of them can forget.
  Future<void> _initializeWith({
    required String url,
    required Map<String, String> headers,
    required String? type,
    Duration resumeAt = Duration.zero,
    PartyPlayback? party,
  }) async {
    var effUrl = url;
    var effHeaders = headers;
    var effType = type;

    // Only when the server sent a directive — no provider check, no url
    // pattern-matching. See `_extractorConfig`.
    final cfg = _extractorConfig;
    if (cfg != null && url.isNotEmpty) {
      _plog('webview sniff: host=${cfg.hostPattern} patterns=${cfg.urlPatterns}');
      final sw = Stopwatch()..start();
      final sniffed = await getIt<WebViewStreamExtractor>().extract(
        pageUrl: url,
        config: cfg,
        pageHeaders: headers,
      );
      if (!mounted) return;
      if (sniffed != null) {
        effUrl = sniffed.url;
        // Sniffed headers win: they are the ones the page actually sent, and
        // the CDN gates on exactly those.
        effHeaders = {...headers, ...sniffed.headers};
        effType = sniffed.playType;
        _plog('sniff ok in ${sw.elapsedMilliseconds}ms -> $effUrl');
        effUrl = await _applyRewrite(cfg.rewrite, effUrl, effHeaders);
      } else {
        // The url in hand is the embed PAGE. Handing that to the player used to
        // cost two doomed retries and a minute of spinner before an error that
        // blamed the format — the page is HTML, so of course no extractor reads
        // it. Say what actually happened, and offer the browser, which is where
        // a player this protected does work.
        _plog('sniff found no stream in ${sw.elapsedMilliseconds}ms',
            level: LogLevel.warn);
        setState(() {
          _initializing = false;
          _isCodecError = true;
          _errorMessage = 'player.stream_not_found'.tr();
        });
        return;
      }
    }

    await _initializeResolved(
      url: effUrl,
      headers: effHeaders,
      type: effType,
      resumeAt: resumeAt,
      party: party,
    );
  }

  Future<void> _initializeResolved({
    required String url,
    required Map<String, String> headers,
    required String? type,
    Duration resumeAt = Duration.zero,
    PartyPlayback? party,
  }) async {
    if (url.isEmpty) {
      setState(() {
        _initializing = false;
        _errorMessage = 'Empty video URL';
      });
      return;
    }

    final stopwatch = Stopwatch()..start();
    final isFileUri = url.startsWith('file://');
    final isLocal = url.startsWith('/') || isFileUri;
    final isHls = _isHlsType(type) || url.toLowerCase().contains('.m3u8');
    final isDash = type?.trim().toLowerCase() == 'dash' ||
        url.toLowerCase().contains('.mpd');
    _isHls = isHls;

    final proxied = !isLocal && isHls
        ? await _maybeRouteThroughLocalProxy(url: url, headers: headers)
        : null;
    final effectiveUrl = proxied?.url ?? url;
    final effectiveHeaders = proxied?.headers ?? headers;

    final fmt = isHls
        ? 'hls'
        : isDash
            ? 'dash'
            : (type ?? 'progressive');
    PlayerLog.instance.setContext({
      'url': effectiveUrl,
      'type': fmt,
      'local': isLocal.toString(),
      'quality': _currentQuality,
    });
    _plog('loading url: $effectiveUrl');
    _plog('type: $fmt (raw=${type ?? 'unknown'}) local: $isLocal');

    PlayerController controller;
    if (isLocal && isHls) {
      final fileUri = isFileUri ? Uri.parse(effectiveUrl) : Uri.file(effectiveUrl);
      controller = PlayerController.networkUrl(
        fileUri,
        formatHint: VideoFormat.hls,
        videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: false),
      );
      _headers = const {};
    } else if (isLocal) {
      final file = isFileUri
          ? File(Uri.parse(effectiveUrl).toFilePath())
          : File(effectiveUrl);
      controller = PlayerController.file(
        file,
        videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: false),
      );
      _headers = const {};
    } else {
      final uri = Uri.parse(effectiveUrl);
      final isLoopback = uri.host == '127.0.0.1' || uri.host == 'localhost';
      final mergedHeaders = <String, String>{};
      if (!isLoopback) {
        mergedHeaders.addAll(<String, String>{
          'User-Agent':
              kSozoUserAgent,
          'Accept': '*/*',
          'Accept-Language': 'uz,ru;q=0.9,en;q=0.8',
        });
        final defaultReferer = _defaultRefererFor(widget.args.provider);
        if (defaultReferer != null) mergedHeaders['Referer'] = defaultReferer;
        mergedHeaders.addAll(effectiveHeaders);
      }

      _plog('provider: ${widget.args.provider}');
      _plog('headers (${mergedHeaders.length}):');
      mergedHeaders.forEach((k, v) {
        _plog('  $k: $v');
      });

      controller = PlayerController.networkUrl(
        uri,
        httpHeaders: mergedHeaders,
        formatHint: isHls
            ? VideoFormat.hls
            : isDash
                ? VideoFormat.dash
                : null,
        videoPlayerOptions: VideoPlayerOptions(
          allowBackgroundPlayback: false,
        ),
      );
      _headers = mergedHeaders;
    }
    _controller = controller;
    _videoUrl = effectiveUrl;
    _mediaType = type;
    _isNetworkVideo = !isLocal;
    // Known BEFORE the first frame, not after it. A channel that is down at the
    // moment you open it fails during initialize(), and the error path has to
    // already know it is looking at a broadcast — otherwise the one case that
    // most needs reconnecting is the one that gets a dead end.
    if (type == 'live' || widget.args.type == 'live') _isLive = true;

    try {
      await controller.initialize();
      _plog('initialize completed in ${stopwatch.elapsedMilliseconds}ms');
      if (!mounted) {
        await controller.dispose();
        return;
      }
      if (controller.value.hasError) {
        final raw = controller.value.errorDescription;
        _plog('init error: $raw', level: LogLevel.error);
        setState(() {
          _initializing = false;
          _errorMessage = raw == null
              ? 'Could not load video'
              : _humanizeError(raw);
        });
        return;
      }
      final dur = controller.value.duration;
      // What the caller said, OR what the duration implies. The declared type is
      // the reliable half: a live channel with a DVR window reports a perfectly
      // finite duration and would otherwise be treated as a file.
      _isLive = _mediaType == 'live' ||
          widget.args.type == 'live' ||
          dur <= Duration.zero ||
          dur.inHours >= 12;
      PlayerLog.instance.setContext({
        'live': _isLive.toString(),
        'duration': _isLive ? 'live' : dur.toString(),
      });
      _plog('initialized — ${_isLive ? 'LIVE stream' : 'duration $dur'}');

      // Engine = External player. Sozo still does the hard part — extraction,
      // header-gated proxying, picking the quality — and then hands the
      // resolved URL to VLC / MX Player. Bail out before autoplay rather than
      // starting playback and immediately pausing it, so there is no burst of
      // audio and no wasted bandwidth. Resume position is NOT carried across:
      // the intent has no standard extra for it, so the external app starts
      // from zero.
      if (ExternalPlayer.isSupported &&
          resolvePlayerEngine() == PlayerEngine.external) {
        _plog('external engine — handing off to a third-party player');
        setState(() {
          _initializing = false;
          _errorMessage = null;
          _isCodecError = false;
        });
        await _handOffToExternalPlayer();
        return;
      }

      if (_canGeneratePreview && !_isLive) {
        FramePreviewService.open(
          _videoUrl!,
          _headers,
          warmMs: resumeAt.inMilliseconds,
        );
      }
      controller.addListener(_onMajorChange);
      await controller.setLooping(false);
      if (party != null) {
        // Watch2Gether: ignore the local resume point and align to the party.
        if ((party.rate - _playbackSpeed).abs() > 0.01) {
          _playbackSpeed = party.rate;
        }
        await controller.setPlaybackSpeed(_playbackSpeed);
        if (!_isLive) {
          final expected = party.expectedPositionAt(DateTime.now());
          if (expected > 0) {
            await controller.seekTo(
              Duration(milliseconds: (expected * 1000).round()),
            );
          }
        }
        if (party.isPlaying) {
          await controller.play();
        }
      } else {
        await controller.setPlaybackSpeed(_playbackSpeed);
        if (resumeAt > Duration.zero && !_isLive) {
          await controller.seekTo(resumeAt);
        }
        await controller.play();
      }
      _plog('play started — total ${stopwatch.elapsedMilliseconds}ms');
      setState(() {
        _initializing = false;
        _errorMessage = null;
      _isCodecError = false;
      });
      _scheduleHide();
    } on PlatformException catch (e) {
      _plog('platform exception ${e.code}: ${e.message}',
          level: LogLevel.error);
      if (!mounted) return;
      final raw = e.message ?? '';
      String msg;
      if (e.code == 'channel-error') {
        msg = 'Player not ready — please fully restart the app';
      } else if (raw.contains('Cannot Decode') ||
          raw.contains('-12906') ||
          raw.contains('-12939') ||
          raw.contains('CoreMediaError')) {
        if (!_autoFallbackUsed && _videoSources.length > 1) {
          _autoRetrying = true;
          _autoRetry();
          return;
        }
        _isCodecError = true;
        msg =
            'This video format is not supported on your device. You can try playing it in your browser.';
      } else if (_isLive && _lifetimeRetries < _kMaxLiveRetries) {
        // A channel that would not open is very often a channel that will open
        // in a moment — the origin was mid-restart, or the playlist rolled. The
        // same reconnect the mid-playback path uses applies here.
        _retryAttempts++;
        _lifetimeRetries++;
        _autoRetrying = true;
        _liveReconnect();
        return;
      } else if (_isRecoverableError(raw) &&
          _retryAttempts < 2 &&
          _lifetimeRetries < _kMaxLifetimeRetries) {
        _plog('recoverable error, retrying (attempt ${_retryAttempts + 1})',
            level: LogLevel.warn);
        _retryAttempts++;
        _lifetimeRetries++;
        _autoRetrying = true;
        _autoRetry();
        return;
      } else {
        msg = raw.isEmpty ? 'Could not load video' : _humanizeError(raw);
      }
      setState(() {
        _initializing = false;
        _errorMessage = msg;
      });
    } catch (e) {
      _plog('init threw: $e', level: LogLevel.error);
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  String _humanizeError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('mediacodec') ||
        lower.contains('decoder') ||
        lower.contains('renderer')) {
      return 'This device couldn\'t decode the video. Try a different quality or retry.';
    }
    if (lower.contains('source error') ||
        lower.contains('unrecognizedinputformat') ||
        lower.contains('nodeclaredbrand')) {
      return 'Couldn\'t open the video source (the server may have blocked it). Try a different quality.';
    }
    if (lower.contains('http data source')) {
      return 'Network error — check your connection';
    }
    if (lower.contains('cannot decode') ||
        lower.contains('-12906') ||
        lower.contains('coremediaerror')) {
      return 'This video format is not supported on your device. Try a different quality.';
    }
    return raw;
  }

  bool _isRecoverableError(String msg) {
    final l = msg.toLowerCase();
    if (l.contains('-12939') ||
        l.contains('-12938') ||
        l.contains('-12660') ||
        l.contains('404') ||
        l.contains('403') ||
        l.contains('not found') ||
        l.contains('forbidden') ||
        l.contains('coremediaerror') ||
        l.contains('cannot decode') ||
        l.contains('-12906')) {
      return false;
    }
    return l.contains('timed out') ||
        l.contains('timeout') ||
        l.contains('-1001') ||
        l.contains('-1005') ||
        l.contains('source error') ||
        l.contains('mediacodec') ||
        l.contains('decoder') ||
        l.contains('renderer');
  }

  void _onMajorChange() {
    final c = _controller;
    if (c == null) return;
    final v = c.value;

    if (v.hasError) {
      final msg = v.errorDescription;
      if (msg != null && msg != _lastError && mounted) {
        _lastError = msg;
        _plog('playback error: $msg', level: LogLevel.error);
        // A live channel reconnects rather than giving up: a drop mid-broadcast
        // is the normal case, not a broken source. It also reconnects on errors
        // a file would call fatal — a 403 or a 404 on a live edge is usually a
        // rotated token or a segment that expired while we were away, and the
        // next playlist fetch has the current one.
        final liveRetry = _isLive && _lifetimeRetries < _kMaxLiveRetries;
        if (!_autoRetrying &&
            (liveRetry ||
                (_retryAttempts < 2 &&
                    _lifetimeRetries < _kMaxLifetimeRetries &&
                    _isRecoverableError(msg)))) {
          _retryAttempts++;
          _lifetimeRetries++;
          _autoRetrying = true;
          if (_isLive) {
            _liveReconnect();
          } else {
            _autoRetry();
          }
          return;
        }
        setState(() => _errorMessage = _humanizeError(msg));
      }
      return;
    }
    if (v.isInitialized) {
      _retryAttempts = 0;
      _autoRetrying = false;
    }

    var changed = false;
    if (v.isInitialized != _wasInitialized) {
      _wasInitialized = v.isInitialized;
      changed = true;
    }
    if (v.isPlaying != _wasPlaying) {
      _wasPlaying = v.isPlaying;
      changed = true;
      if (_isPip) _refreshPipActions();
      if (v.isPlaying) {
        _playbackWatch.start();
        _scheduleHistorySave();
      } else {
        _playbackWatch.stop();
        _saveHistory();
      }
    }
    if (!_streakPingScheduled && _playbackWatch.elapsed.inSeconds >= 60) {
      _streakPingScheduled = true;
      _pingStreak();
    }
    if (v.isBuffering != _wasBuffering) {
      _wasBuffering = v.isBuffering;
      changed = true;
    }

    if (v.isInitialized && v.duration.inMilliseconds > 0) {
      if (v.position.inMilliseconds >=
          v.duration.inMilliseconds * _kTrackerThreshold) {
        _maybeReportTrackers();
      }

      final remaining = v.duration - v.position;
      final isEnding = remaining <= const Duration(seconds: 2);
      if (isEnding) {
        // Guests in a party never self-advance — they wait for the host's
        // next party:content. The host auto-advances and emits it.
        final guestInParty = _inParty && !_isPartyHost;
        // Auto-advance is opt-out, not opt-in: it is what the player has
        // always done. Turning it off leaves the episode parked on its last
        // frame, which is also what makes the history entry below correct.
        if (!guestInParty &&
            _hive.autoPlayNextEpisode &&
            widget.args.isSerial &&
            _episodeIndex + 1 < widget.args.episodes.length) {
          _saveHistoryForNextEpisode();
          _loadEpisode(_episodeIndex + 1);
          return;
        }
        final url = widget.args.contentUrl;
        if (url != null && url.isNotEmpty) {
          _history.remove(url);
        }
      }
    }

    if (changed && mounted) setState(() {});
  }

  /// Reconnects a dropped live channel, backing off between attempts.
  ///
  /// Deliberately NOT [_autoRetry]: that one's first move is to fall through to
  /// the next quality source, which for a channel with a single url is a no-op,
  /// and its second is to surface an error. A broadcast has nowhere else to go —
  /// the same url IS the channel — so this reopens it, waits longer each time,
  /// and keeps the last frame on screen instead of flashing an error at somebody
  /// whose stream will be back in two seconds.
  Future<void> _liveReconnect() async {
    if (!mounted) return;
    final attempt = _lifetimeRetries;
    _plog('live stream dropped — reconnecting (attempt $attempt)');

    setState(() {
      _stage = _LoadingStage.loading;
      _errorMessage = null;
      _isCodecError = false;
    });

    await Future<void>.delayed(_liveRetryBackoff(attempt - 1));
    if (!mounted) return;

    final url = _videoUrl;
    if (url == null) {
      _autoRetrying = false;
      return;
    }
    await _disposeController();
    if (!mounted) return;
    await _initializeWith(url: url, headers: _headers, type: _mediaType);
    _autoRetrying = false;
  }

  Future<void> _autoRetry() async {
    if (!mounted) return;

    if (!_autoFallbackUsed &&
        _videoSources.length > 1 &&
        _currentSourceIndex >= 0 &&
        _currentSourceIndex + 1 < _videoSources.length) {
      final nextIdx = _currentSourceIndex + 1;
      final next = _videoSources[nextIdx];
      _autoFallbackUsed = true;
      setState(() {
        _initializing = true;
        _stage = _LoadingStage.loading;
        _errorMessage = null;
      _isCodecError = false;
        _currentSourceIndex = nextIdx;
        _currentQuality = next.quality;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Switching to ${next.quality}...'),
            backgroundColor: Colors.black87,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      await _disposeController();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      await _initializeWith(
        url: next.videoUrl,
        headers: _headers.isNotEmpty ? _headers : widget.args.headers,
        type: _mediaType,
      );
      _autoRetrying = false;
      return;
    }

    setState(() {
      _initializing = true;
      _stage = widget.args.isSerial
          ? _LoadingStage.resolving
          : _LoadingStage.loading;
      _errorMessage = null;
      _isCodecError = false;
    });
    await _disposeController();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    if (widget.args.isSerial) {
      await _loadEpisode(_episodeIndex, keepRetryCount: true);
    } else if (_videoUrl != null) {
      await _initializeWith(
        url: _videoUrl!,
        headers: _headers,
        type: _mediaType,
      );
    } else {
      await _bootstrap();
    }
    _autoRetrying = false;
  }

  Future<void> _disposeController() async {
    _hideTimer?.cancel();
    final c = _controller;
    if (c != null) {
      c.removeListener(_onMajorChange);
      try {
        await c.pause();
      } catch (_) {}
      await c.dispose();
    }
    _controller = null;
    _wasPlaying = false;
    _wasBuffering = false;
    _wasInitialized = false;
    _lastError = null;
  }

  String _episodeTitle() {
    if (!widget.args.isSerial) return widget.args.title;
    final ep = widget.args.episodes[_episodeIndex];
    final fallback = 'Episode ${ep.episode}';
    final label = ep.label.trim().isEmpty ? fallback : ep.label;
    return '${widget.args.title} · $label';
  }

  Future<void> _retry() async {
    if (widget.args.isSerial) {
      await _loadEpisode(_episodeIndex);
    } else if (_videoUrl != null) {
      setState(() {
        _initializing = true;
        _stage = _LoadingStage.loading;
        _errorMessage = null;
      _isCodecError = false;
      });
      await _disposeController();
      await _initializeWith(
        url: _videoUrl!,
        headers: _headers,
        type: _mediaType,
      );
    }
  }

  Future<void> _loadThumbnails(ThumbnailsEntity? thumbnails) async {
    if (thumbnails == null) {
      _thumbnailsKey = null;
      _vttThumbnails = const [];
      _storyboard = null;
      return;
    }
    if (thumbnails.isStoryboard) {
      final key = 'sb:${thumbnails.template}';
      if (key == _thumbnailsKey && _storyboard != null) return;
      _thumbnailsKey = key;
      _vttThumbnails = const [];
      _storyboard = thumbnails;
      return;
    }
    if (!thumbnails.isVtt) {
      _thumbnailsKey = null;
      _vttThumbnails = const [];
      _storyboard = null;
      return;
    }
    final url = thumbnails.url!;
    final key = 'vtt:$url';
    if (key == _thumbnailsKey && _vttThumbnails.isNotEmpty) return;
    _thumbnailsKey = key;
    _storyboard = null;
    try {
      final response = await Dio().get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: thumbnails.headers.isEmpty ? null : thumbnails.headers,
        ),
      );
      if (!mounted) return;
      final body = response.data;
      if (body != null && body.isNotEmpty) {
        _vttThumbnails = _VttThumbnail.parse(body, url);
        _plog('loaded ${_vttThumbnails.length} VTT thumbnails');
      }
    } catch (e) {
      _plog('VTT thumbnails load error: $e', level: LogLevel.warn);
      _vttThumbnails = const [];
    }
  }

  bool get _hasThumbnails =>
      _vttThumbnails.isNotEmpty || _storyboard != null;

  _VttThumbnail? _thumbnailAt(Duration position) {
    final sb = _storyboard;
    if (sb != null && sb.isStoryboard) {
      final c = _controller;
      final durMs = c != null && c.value.isInitialized
          ? c.value.duration.inMilliseconds
          : 0;
      if (durMs <= 0) return null;
      final cols = sb.columns!;
      final rows = sb.rows!;
      final totalCells = cols * rows;
      final ratio = position.inMilliseconds / durMs;
      final idx = (ratio * totalCells)
          .clamp(0, totalCells - 1)
          .floor();
      final col = idx % cols;
      final row = idx ~/ cols;
      final cellW = (sb.width! / cols).round();
      final cellH = (sb.height! / rows).round();
      return _VttThumbnail(
        start: Duration.zero,
        end: Duration.zero,
        imageUrl: sb.template!,
        x: col * cellW,
        y: row * cellH,
        w: cellW,
        h: cellH,
      );
    }
    for (final t in _vttThumbnails) {
      if (t.contains(position)) return t;
    }
    return null;
  }
}
