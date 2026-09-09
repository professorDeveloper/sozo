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
      _resetLadder();
      _currentSourceIndex =
          _ladder(_videoSources, hasDirective: widget.args.extractor != null)
                  .initialPick() ??
              -1;
      // A serial re-resolves inside _loadEpisode and picks the directive up
      // there. A movie was resolved back on the detail page, so the only copy
      // of it is the one that travelled in the args — and without it
      // _initializeWith skips the sniff and hands the player an embed page.
      _extractorConfig = widget.args.extractor;
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

  /// Loads the page holding [absoluteIndex] and plays that episode.
  ///
  /// The window is REPLACED rather than appended to. Appending would grow the
  /// list without bound across a long binge, and every index the player holds
  /// is relative to the window — so a window that changes length underneath
  /// them is worse than one that moves wholesale with `_windowStart`.
  ///
  /// A failure leaves everything as it was. Half-applying this — moving
  /// `_windowStart` without the episodes, or the reverse — would make every
  /// later index point at the wrong episode, and the first visible symptom
  /// would be the wrong title written to history.
  Future<void> _loadAcrossPage(
    int absoluteIndex, {
    Duration resumeAt = Duration.zero,
  }) async {
    final size = widget.args.pageSize;
    final contentUrl = widget.args.contentUrl;
    if (size <= 0 || contentUrl == null || contentUrl.isEmpty) return;

    final page = absoluteIndex ~/ size + 1;
    setState(() {
      _initializing = true;
      _stage = _LoadingStage.resolving;
      _errorMessage = null;
    });

    final result = await getIt<GetEpisodesUseCase>()(
      contentUrl,
      page: page,
      size: size,
      sort: widget.args.sort,
      provider: widget.args.provider,
    );
    if (!mounted) return;

    switch (result) {
      case Success(:final value):
        final fetched = value.episodes;
        if (fetched.isEmpty) {
          setState(() {
            _initializing = false;
            _errorMessage = 'player.episode_page_failed'.tr();
          });
          return;
        }
        // One operation. The old pair set the list and the offset separately
        // and then recomputed the window-relative index at the call below —
        // three chances to disagree about where the playhead is.
        setState(() {
          _window = _window.withPage(
            fetched,
            page: value.page,
            pageSize: size,
            absoluteIndex: absoluteIndex,
          );
        });
        await _loadEpisode(_window.index, resumeAt: resumeAt);
      case Failure():
        setState(() {
          _initializing = false;
          _errorMessage = 'player.episode_page_failed'.tr();
        });
    }
  }

  /// Plays the episode at window-relative [index].
  ///
  /// Five steps, each its own method. They were one 127-line function, and the
  /// order between them was an unwritten condition: `_resetForEpisode` has to
  /// run BEFORE the teardown, or the retry path resets the very state it just
  /// set and walks back onto the mirror that failed. Naming the steps is what
  /// makes that order visible at the call site instead of implied by position
  /// inside a long body.
  Future<void> _loadEpisode(
    int index, {
    Duration resumeAt = Duration.zero,
    bool keepRetryCount = false,
  }) async {
    if (await _pageAcrossIfNeeded(index, resumeAt: resumeAt)) return;

    _resetForEpisode(index, keepRetryCount: keepRetryCount);
    await _tearDownForEpisode();
    if (!mounted) return;

    final ep = _episodes[index];
    final resolved = await _resolveEpisode(ep);
    if (!mounted || resolved == null) return;

    await _startPlayback(ep, resolved.value, lang: resolved.lang, resumeAt: resumeAt);
  }

  /// Handles an index outside the loaded window.
  ///
  /// Returns true when it took over — the caller is done, because paging
  /// re-enters `_loadEpisode` against the new window.
  ///
  /// This is what turns "Next is greyed out at episode 100" into a series that
  /// actually plays through. It costs a network call between episodes, which is
  /// why it happens only when the window genuinely runs out.
  Future<bool> _pageAcrossIfNeeded(
    int index, {
    required Duration resumeAt,
  }) async {
    if (_window.contains(index)) return false;
    final absolute = _windowStart + index;
    // Off the end of the SERIES, or a provider that cannot page: nothing to
    // fetch, and returning true stops the caller playing a nonexistent episode.
    if (!_window.containsAbsolute(absolute)) return true;
    if (!widget.args.isWindowed) return true;
    await _loadAcrossPage(absolute, resumeAt: resumeAt);
    return true;
  }

  /// Everything that must NOT survive from the previous episode.
  ///
  /// [keepRetryCount] is what separates "a new episode" from "another attempt
  /// at this one": the retry path passes true precisely so the ladder and the
  /// counters are left alone, and resetting them there would loop between the
  /// first two mirrors forever.
  void _resetForEpisode(int index, {required bool keepRetryCount}) {
    if (!keepRetryCount) {
      _retryAttempts = 0;
      _lifetimeRetries = 0;
      _resetLadder();
      // A crop tuned for a 2.39:1 film is wrong for the 16:9 episode after it.
      _resetZoom();
    }
    // The previous episode's opening/ending times do not apply to this one,
    // and leaving them would offer a skip at the wrong minute.
    _resetSkipTimes();
    // A new episode is a new thing to finish. Without this, watching six in a
    // row would count as one.
    _countedComplete = false;
    // And a new episode is a new question for the auto-translator: episode 4
    // may carry a subtitle in the viewer's language when episode 3 did not.
    _autoTranslateDone = false;
    setState(() {
      _initializing = true;
      _stage = _LoadingStage.resolving;
      _errorMessage = null;
      _isCodecError = false;
      _window = _window.at(index);
      _panel = _SidePanel.none;
    });
  }

  /// Closes the previous stream and lets the engine settle.
  ///
  /// The delay is not decoration: disposing and immediately re-initialising a
  /// native surface is how a black frame survives into the next episode.
  Future<void> _tearDownForEpisode() async {
    // Sync is per-episode: a shift/rate tuned for the previous episode is wrong
    // here, so drop it and load whatever was saved for this one (0 / 1.0 when
    // nothing was).
    _restoreSubtitleSync();
    await _disposeController();
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  /// Resolves [ep], or reports why it could not be played and returns null.
  Future<({MediaResolveEntity value, String? lang})?> _resolveEpisode(
    EpisodeEntity ep,
  ) async {
    if (ep.mediaRef.isEmpty) {
      setState(() {
        _initializing = false;
        _errorMessage = PlaybackFaultKind.noSourceForEpisode.messageKey.tr();
      });
      return null;
    }

    final lang = _resolveLangForEpisode(ep);
    final resolveSw = Stopwatch()..start();
    _plog('resolving ref=${ep.mediaRef} lang=$lang');
    final result = await _resolve(
      ref: ep.mediaRef,
      provider: widget.args.provider,
      lang: lang,
    );
    _plog('resolve completed in ${resolveSw.elapsedMilliseconds}ms');
    if (!mounted) return null;

    switch (result) {
      case Success(:final value):
        return (value: value, lang: lang);
      case Failure(:final error):
        setState(() {
          _initializing = false;
          _errorMessage = error.toString().replaceFirst('Exception: ', '');
        });
        return null;
    }
  }

  /// Picks a mirror, publishes the new episode's state, and starts the stream.
  Future<void> _startPlayback(
    EpisodeEntity ep,
    MediaResolveEntity value, {
    required String? lang,
    required Duration resumeAt,
  }) async {
    final sources = value.videoSources;
    // `sources[0]` was taken outright here, so the remembered quality was
    // honoured on a movie and ignored on every episode of a serial — and an
    // iframe entry, which some providers put first, went straight to the
    // decoder as if it were a stream.
    final pickedIdx = _ladder(
          sources,
          hasDirective: value.extractor != null,
        ).initialPick() ??
        -1;
    final useSources = pickedIdx >= 0;
    final url = useSources ? sources[pickedIdx].videoUrl : value.videoUrl;
    final subs = value.subtitles;

    setState(() {
      _stage = _LoadingStage.loading;
      _serverLangs = value.languagesAvailable;
      _currentLang = lang ?? value.activeLang ?? _currentLang;
      _videoSources = useSources ? List.of(sources) : const [];
      _currentSourceIndex = pickedIdx;
      _currentQuality = useSources ? sources[pickedIdx].quality : null;
      _subtitles = subs;
      _activeSubtitleIndex = -1;
      _captionFile = null;
      _secondarySubtitleIndex = -1;
      _secondaryCaptionFile = null;
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
  }

  /// The index of the source this title was last watched on, if it is still
  /// offered.
  ///
  /// Null rather than a fallback, so the caller keeps its own default: a
  /// remembered mirror that has since disappeared must not silently become
  /// "whatever is at that position now", which would be a different server
  /// with the same index.
  /// The ladder over [sources], carrying everything already tried.
  SourceLadder _ladder(
    List<VideoSourceEntity> sources, {
    required bool hasDirective,
  }) =>
      SourceLadder(
        sources: sources,
        hasDirective: hasDirective,
        rememberedQuality: SourceLadder.rememberedQualityFor(
          _titlePrefs,
          provider: widget.args.provider,
          contentUrl: widget.args.contentUrl ?? '',
        ),
        avoidCodec: _decoderAvoidCodec,
        triedUrls: _triedSourceUrls,
      );

  /// Starts a fresh walk. Called wherever what is playing genuinely changes —
  /// a new episode, a new movie, an explicit pick — never on a retry, which is
  /// the whole point of keeping the set.
  void _resetLadder() {
    _triedSourceUrls.clear();
    _decoderAvoidCodec = null;
  }

  /// Whether any mirror is left. This is the condition an error screen should
  /// wait for; a single failure never was one.
  bool get _hasUntriedSource =>
      _ladder(_videoSources, hasDirective: _extractorConfig != null).next() !=
      null;

  /// Marks what is on screen as attempted, so the ladder moves past it.
  void _markCurrentTried() {
    if (_currentSourceIndex >= 0 && _currentSourceIndex < _videoSources.length) {
      _triedSourceUrls.add(_videoSources[_currentSourceIndex].videoUrl);
    }
  }

  /// Downloads the chain if needed, then hands it to the player.
  ///
  /// Silent on every failure. Somebody who turned this on with no connection
  /// gets the picture they had yesterday, not an episode that will not start —
  /// and a chain that is only half fetched is never applied at all, because a
  /// missing link makes mpv fail to initialise video output, which presents as
  /// a black screen rather than as a missing enhancement.
  Future<void> _applyShaders(PlayerController controller) async {
    if (!controller.supportsShaders) return;
    if (_shaderPreset.isOff) {
      await controller.setShaders(const []);
      return;
    }
    final paths = await _shaders.ensure(_shaderPreset, _shaderTier);
    if (paths == null || paths.isEmpty || !mounted) return;
    if (!identical(controller, _controller)) return;
    await controller.setShaders(paths);
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
    if (_episodeIndex < 0 || _episodeIndex >= _episodes.length) {
      return const [];
    }
    final epLangs = _episodes[_episodeIndex].availableLangs;
    if (epLangs.isNotEmpty) return epLangs;
    return _serverLangs;
  }

  Future<void> _switchLang(String lang) async {
    if (!widget.args.isSerial) return;
    if (lang == _currentLang) return;
    final keepPosition = _controller?.value.position ?? Duration.zero;
    setState(() => _currentLang = lang);
    // Both: for this title, because that is the choice being made, and as the
    // global default, because changing it here almost always means "this is
    // what I want from now on" for anything new.
    await _titlePrefs.rememberLang(
      widget.args.provider,
      widget.args.contentUrl ?? '',
      lang,
    );
    await _hive.savePreferredMediaLang(lang);
    await _loadEpisode(_episodeIndex, resumeAt: keepPosition);
  }

  Future<void> _switchQuality(VideoSourceEntity source) async {
    if (source.quality == _currentQuality) {
      setState(() => _panel = _SidePanel.none);
      return;
    }
    // Remembered for this title. Plenty of shows only play on their third
    // mirror, and re-picking it every episode is the kind of chore that reads
    // as the app not working.
    unawaited(
      _titlePrefs.rememberQuality(
        widget.args.provider,
        widget.args.contentUrl ?? '',
        source.quality,
      ),
    );
    final keepPosition = _controller?.value.position ?? Duration.zero;
    final idx = _videoSources.indexWhere((s) => s.quality == source.quality);
    _retryAttempts = 0;
    _lifetimeRetries = 0;
    // A deliberate pick is a fresh walk — the same reset the retry counters get
    // on this line, and what `_autoFallbackUsed = false` used to do here.
    // Without it the tried-set from a failed auto-walk survives, so the next
    // recoverable hiccup re-resolves and drops the viewer back onto sources[0],
    // a mirror already known to fail, off the one they just chose by hand.
    _resetLadder();
    setState(() {
      _initializing = true;
      _stage = _LoadingStage.loading;
      _errorMessage = null;
      _isCodecError = false;
      _currentQuality = source.quality;
      _currentSourceIndex = idx >= 0 ? idx : _currentSourceIndex;
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
        _expandMasterPlaylist(candidate, body, headers);
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

  /// Turn a verified master playlist into one [VideoSourceEntity] per rendition.
  ///
  /// A hybrid provider cannot enumerate qualities when it resolves: the manifest
  /// URL only exists after the device has sniffed the embed, so the server can
  /// only hand back a single `auto` source. ExoPlayer still adapts across every
  /// rendition inside the master, but the quality sheet reads [_videoSources] —
  /// so with one entry there is nothing to open and the picker never appears,
  /// even though four renditions are playing.
  ///
  /// [_applyRewrite] already holds the master's body: it fetched it to prove the
  /// rewrite was real. Parsing it here costs no extra request and turns those
  /// renditions into entries the sheet can list.
  ///
  /// `auto` stays first and stays selected — adaptive is the better default on a
  /// phone, and the explicit heights are there for when the viewer wants to pin
  /// one.
  void _expandMasterPlaylist(
    String masterUrl,
    String body,
    Map<String, String> headers,
  ) {
    // Only ever widens a source list the provider could not fill in. A list
    // that already has real qualities came from the provider and is better
    // than anything parsed here.
    if (_videoSources.length > 1) return;

    final base = Uri.tryParse(masterUrl);
    if (base == null) return;

    final variants = <({int height, String url})>[];
    final lines = body.split(RegExp(r'\r?\n'));
    for (var i = 0; i < lines.length - 1; i++) {
      final tag = lines[i].trim();
      if (!tag.startsWith('#EXT-X-STREAM-INF')) continue;
      final uri = lines[i + 1].trim();
      if (uri.isEmpty || uri.startsWith('#')) continue;
      // The label comes from the variant's own name when it has one, and only
      // falls back to RESOLUTION. They disagree more often than not: a 2.40:1
      // film encoded at 1080p carries RESOLUTION=1920x800, so naming the row
      // after the pixel height offers the viewer `800p` for the stream every
      // other player calls 1080p. The `index-s1080p-v1-a1` token in the URI is
      // the name the packager gave it.
      final named = RegExp(r'[-_/]s(\d{3,4})p\b').firstMatch(uri);
      final res = RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(tag);
      final height =
          int.tryParse(named?.group(1) ?? res?.group(1) ?? '') ?? 0;
      if (height <= 0) continue;
      variants.add((height: height, url: base.resolve(uri).toString()));
    }
    if (variants.isEmpty) return;

    // Best first, and one entry per height: a master often carries the same
    // resolution twice at different bitrates, which would show the sheet two
    // rows both labelled `1080p`.
    variants.sort((a, b) => b.height.compareTo(a.height));
    final seen = <int>{};

    final auto = _videoSources.isNotEmpty ? _videoSources.first : null;
    final expanded = <VideoSourceEntity>[
      VideoSourceEntity(
        quality: 'auto',
        videoUrl: masterUrl,
        isDefault: true,
        accessible: true,
        type: auto?.type ?? 'hls',
        headers: auto?.headers ?? headers,
      ),
      for (final v in variants)
        if (seen.add(v.height))
          VideoSourceEntity(
            quality: '${v.height}p',
            videoUrl: v.url,
            isDefault: false,
            accessible: true,
            type: auto?.type ?? 'hls',
            headers: auto?.headers ?? headers,
          ),
    ];

    _plog('master playlist -> ${expanded.length - 1} qualities '
        '(${expanded.skip(1).map((e) => e.quality).join(", ")})');
    if (!mounted) return;
    setState(() {
      _videoSources = expanded;
      _currentSourceIndex = 0;
    });
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
        // One embed page that hid its stream used to end playback outright,
        // with every sibling mirror untried. It is one failed candidate: mark
        // it and walk on. The error below is what happens once the ladder is
        // genuinely exhausted.
        _markCurrentTried();
        if (_hasUntriedSource) {
          _autoRetrying = true;
          unawaited(_autoRetry());
          return;
        }
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
        _errorMessage = PlaybackFaultKind.emptyUrl.messageKey.tr();
      });
      return;
    }

    // A magnet or .torrent link is not a stream, and handing one to ExoPlayer
    // produces a bare "Source error". Turning it into a local HTTP stream here
    // — the single funnel every playback path passes through — means Sozo's own
    // torrent search, a CloudStream plugin that returns a magnet, and a pasted
    // deeplink all behave identically, instead of each growing its own version.
    if (TorrentLinks.isTorrentLink(url)) {
      final handle = await TorrentPlayback.prepareLink(
        context,
        url,
        engine: _torrentEngine,
        title: widget.args.title,
      );
      if (!mounted) return;
      // Null means the user declined the privacy warning, cancelled, or the
      // swarm never answered — all of which prepareLink has already reported.
      // Closing is the honest response; an error screen would be a second
      // message about the same thing.
      if (handle == null) {
        setState(() => _initializing = false);
        Navigator.of(context).maybePop();
        return;
      }
      _torrentHash = handle.hash;
      url = handle.url.toString();
      // Whatever the plugin claimed the type was described the torrent, not
      // the file inside it, and the server serves plain ranged bytes.
      type = 'progressive';
      headers = const {};
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

      // The source being played decides whether this stream is encrypted, so
      // it is read here rather than carried on the page: switching quality or
      // mirror can move between an encrypted rendition and a clear one, and the
      // backend has to follow.
      final drm = _currentSourceIndex >= 0 &&
              _currentSourceIndex < _videoSources.length
          ? _videoSources[_currentSourceIndex].drm
          : null;
      if (drm != null) _plog('drm: $drm');

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
        drm: drm,
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
        // The other half of the pair. Only the CATEGORY of failure travels —
        // "codec", "network" — never the url or the message, which carry the
        // token and the title.
        getIt<Analytics>().track(
          AnalyticsEvent.playbackFailed,
          props: {
            AnalyticsProp.provider: widget.args.provider,
            AnalyticsProp.engine: resolvePlayerEngine().id,
            AnalyticsProp.reason: _isCodecError ? 'codec' : 'load',
          },
        );
        setState(() {
          _initializing = false;
          _errorMessage = raw == null
              ? PlaybackFaultKind.unknown.messageKey.tr()
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

      // Counted here, where a decoded frame actually exists — not where play
      // was tapped. The gap between the two is the whole failure surface this
      // app has, and an event fired on the tap would report every black screen
      // as a successful play.
      getIt<Analytics>().track(
        AnalyticsEvent.playbackStarted,
        props: {
          AnalyticsProp.provider: widget.args.provider,
          AnalyticsProp.engine: resolvePlayerEngine().id,
          AnalyticsProp.kind: _isLive ? 'live' : (widget.args.type ?? 'video'),
        },
      );

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
        //
        // A bare assignment, unlike the one in _applyRemoteSync, and only
        // because this method ends in a setState of its own a few lines below —
        // the Speed button's label is repainted by that. It is written here
        // rather than there because the awaits in between read it.
        if (PartyRules.needsRateChange(_playbackSpeed, party.rate)) {
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
      // Guarded, because everything between initialize() and here is awaited —
      // a seek, a speed change, the play itself — and a slow source spends
      // seconds in that stretch. Seconds spent staring at a spinner is exactly
      // when someone backs out, and coming back to a disposed State throws.
      if (!mounted) return;
      // After play, not before: mpv rejects equalizer properties until a video
      // output exists, so applying it any earlier silently does nothing and the
      // profile appears not to work on the first episode of a session.
      if (!_colorProfile.isNeutral) {
        unawaited(controller.setColorProfile(_colorProfile));
      }
      // Unawaited, and deliberately after playback is running: the first use
      // downloads up to 300 KB of shader source, and making the episode wait
      // on that would turn an enhancement into a delay. The picture sharpens a
      // moment in, which is the right trade — nobody notices the transition,
      // everybody notices a player that will not start.
      unawaited(_applyShaders(controller));
      setState(() {
        _initializing = false;
        _errorMessage = null;
        _isCodecError = false;
      });
      _scheduleHide();
      // After the duration is known: AniSkip uses episode length to reject
      // submissions timed against a different cut. Unawaited because a skip
      // offer is an extra — playback must never wait on a third-party lookup.
      unawaited(_loadSkipTimes());
      // After the provider's own tracks have been set, so it can see whether
      // one of them already reads in the viewer's language. Unawaited and
      // silent unless it finds something: playback must never wait on it.
      unawaited(_maybeAutoTranslate());
    } on PlatformException catch (e) {
      _plog('platform exception ${e.code}: ${e.message}',
          level: LogLevel.error);
      if (!mounted) return;
      final raw = e.message ?? '';
      String msg;
      if (e.code == 'channel-error') {
        msg = PlaybackFaultKind.engineUnavailable.messageKey.tr();
      } else if (_isDecoderError(raw)) {
        // The codec is the likeliest culprit, so siblings encoded the same way
        // go to the back of the ladder rather than being tried in turn.
        _decoderAvoidCodec = _currentSourceIndex >= 0 &&
                _currentSourceIndex < _videoSources.length
            ? _videoSources[_currentSourceIndex].codec
            : null;
        // Marked first: _hasUntriedSource asks whether anything is LEFT, and
        // the mirror that just failed to decode is not. Testing before marking
        // counted it as a candidate, so a single-mirror codec failure spent a
        // snackbar, a teardown and a full re-resolve arriving back at the same
        // undecodable file instead of saying so immediately.
        _markCurrentTried();
        if (_hasUntriedSource) {
          _retryAttempts++;
          _lifetimeRetries++;
          _autoRetrying = true;
          _autoRetry();
          return;
        }
        _isCodecError = true;
        msg = PlaybackFaultKind.unsupportedFormat.messageKey.tr();
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
        msg = raw.isEmpty
            ? PlaybackFaultKind.unknown.messageKey.tr()
            : _humanizeError(raw);
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

  /// A failure, in the viewer's language.
  ///
  /// Classification lives in [PlaybackFault] where it can be tested without a
  /// widget; this only renders it. `unknown` keeps the engine's own words —
  /// an untranslated detail is more use than a translated non-answer.
  String _faultMessage(PlaybackFault fault) {
    if (fault.kind == PlaybackFaultKind.unknown && fault.raw.isNotEmpty) {
      return fault.raw;
    }
    return fault.messageKey.tr();
  }

  String _humanizeError(String raw) =>
      _faultMessage(PlaybackFault.classify(raw));

  /// Whether the device simply cannot decode this stream.
  ///
  /// Distinct from a recoverable error, and the distinction is the whole point:
  /// a decoder that lacks the profile will lack it again in a second, so
  /// retrying the same url is a guaranteed second failure and a wasted wait.
  /// The right move is a different source, which is what the caller does with
  /// this.
  ///
  /// Both platforms are covered here. Only the iOS spellings were, so on
  /// Android a 4K HEVC Main10 file on a device with no such decoder fell
  /// through to the retry branch and was fetched twice — the log reads
  /// "recoverable error, retrying (attempt 1)" against
  /// `format_supported=NO_EXCEEDS_CAPABILITIES`, which is precisely the one
  /// thing that cannot be recovered by trying again.
  /// Both classifiers moved to [RetryPolicy], where they are testable without
  /// a controller. These forward so the twenty-odd call sites did not have to
  /// change in the same commit.
  static bool _isDecoderError(String raw) => RetryPolicy.isDecoderError(raw);

  bool _isRecoverableError(String msg) =>
      RetryPolicy.isRecoverableError(msg);

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
        // A decoder failure mid-playback is the same fault as one at init: this
        // encode does not play on this device, another mirror may. _isRecoverable
        // deliberately returns false for it, so without this the walk stopped
        // here with untried mirrors left and the viewer had to open Quality and
        // pick one by hand.
        if (!_autoRetrying && _isDecoderError(msg)) {
          _decoderAvoidCodec = _currentSourceIndex >= 0 &&
                  _currentSourceIndex < _videoSources.length
              ? _videoSources[_currentSourceIndex].codec
              : null;
          _markCurrentTried();
          if (_hasUntriedSource && _lifetimeRetries < _kMaxLifetimeRetries) {
            _retryAttempts++;
            _lifetimeRetries++;
            _autoRetrying = true;
            _autoRetry();
            return;
          }
          setState(() => _isCodecError = true);
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
      if (WatchProgress.isWatched(v.position, v.duration)) {
        _maybeReportTrackers();
        // Counted at the same threshold the trackers use, and once per
        // episode: a viewer who scrubs back and forth across the 85% mark must
        // not add a completion each time they cross it.
        if (!_countedComplete) {
          _countedComplete = true;
          if (!_hive.isIncognito) unawaited(_watchStats.recordCompleted());
        }
      }

      _updateActiveSkip(v.position);

      final remaining = v.duration - v.position;
      final isEnding = remaining <= const Duration(seconds: 2);
      if (isEnding) {
        // Guests in a party never self-advance — they wait for the host's
        // next party:content. The host auto-advances and emits it.
        final guestInParty = _inParty && !_isPartyHost;
        // Auto-advance is opt-out, not opt-in: it is what the player has
        // always done. Turning it off leaves the episode parked on its last
        // frame, which is also what makes the history entry below correct.
        // A sleep timer set to "end of episode" parks here rather than
        // advancing. It deliberately reuses the auto-advance-off path below,
        // so the episode is marked finished exactly as it would be for someone
        // who turned auto-advance off — the timer changes when playback stops,
        // not what counts as watched.
        if (!guestInParty &&
            !_sleepAtEpisodeEnd &&
            _hive.autoPlayNextEpisode &&
            widget.args.isSerial &&
            _hasNextEpisode) {
          _saveHistoryForNextEpisode();
          _loadEpisode(_episodeIndex + 1);
          return;
        }
        final url = widget.args.contentUrl;
        if (url != null && url.isNotEmpty) {
          _history.remove(url);
        }
        if (_sleepAtEpisodeEnd) unawaited(_fireSleepTimer());
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

    // Every remaining mirror, in ladder order — not `+ 1` once and done.
    _markCurrentTried();
    final nextIdx =
        _ladder(_videoSources, hasDirective: _extractorConfig != null).next();
    if (nextIdx != null) {
      final next = _videoSources[nextIdx];
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
            content:
                Text('player.switching_to'.tr(args: [next.quality])),
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
    final ep = _episodes[_episodeIndex];
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
