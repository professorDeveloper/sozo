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

  /// The format hint for playing [source]: its own when the provider stated
  /// one, else what the resolve said about the media as a whole.
  ///
  /// Switching mirror used to reuse whatever the previous mirror was played
  /// as, so going from an HLS server to an MP4 one told the engine to expect a
  /// playlist — and the decoder failure that followed was blamed on the new
  /// server.
  String? _typeOf(VideoSourceEntity? source) {
    final own = source?.type?.trim();
    return (own != null && own.isNotEmpty) ? own : _resolvedType;
  }

  /// The headers a network stream is requested with: the app's defaults, then
  /// whatever the source asked for on top.
  ///
  /// Nothing at all for loopback — the local HLS proxy already carries the
  /// upstream headers, and it is our own server.
  Map<String, String> _mergedStreamHeaders(
    Uri uri,
    Map<String, String> sourceHeaders,
  ) {
    if (uri.host == '127.0.0.1' || uri.host == 'localhost') return {};
    final merged = <String, String>{
      'User-Agent': kSozoUserAgent,
      'Accept': '*/*',
      'Accept-Language': 'uz,ru;q=0.9,en;q=0.8',
    };
    final defaultReferer = _defaultRefererFor(widget.args.provider);
    if (defaultReferer != null) merged['Referer'] = defaultReferer;
    merged.addAll(sourceHeaders);
    addFetchMetadata(merged, uri);
    return merged;
  }

  /// The same headers, plus any Cloudflare clearance already earned for this
  /// host.
  ///
  /// The app can solve a challenge — [CfBypassService] does it headlessly and
  /// the interactive solver does it in front of the viewer — and the Dio
  /// client and the JS runtime both send the result. The PLAYER never did. So
  /// a stream host behind Cloudflare was fetched with no cookie at all, by the
  /// one part of the app that has to fetch it dozens of times per episode, and
  /// solving the challenge changed nothing about playback. The jar travels
  /// whole because Cloudflare pairs cf_clearance with the `__cf_bm` and
  /// `_cfuvid` it was issued alongside; the User-Agent above is already the
  /// one those were issued to, which is the other half of making them work.
  ///
  /// Best-effort: a host with nothing in the jar is the ordinary case and adds
  /// no header at all.
  Future<Map<String, String>> _streamHeaders(
    Uri uri,
    Map<String, String> sourceHeaders,
  ) async {
    final merged = _mergedStreamHeaders(uri, sourceHeaders);
    if (merged.isEmpty || merged.containsKey('Cookie')) return merged;
    try {
      final jar = await getIt<CfBypassService>().readClearance(uri.host);
      if (jar != null && jar.isNotEmpty) merged['Cookie'] = jar;
    } catch (_) {
      // A stream that plays without a cookie must not fail because the jar
      // could not be read.
    }
    return merged;
  }

  Future<void> _bootstrap() async {
    final resume = widget.args.resumePosition;
    if (widget.args.isSerial) {
      await _loadEpisode(_episodeIndex, resumeAt: resume);
    } else {
      _videoSources = List.of(widget.args.videoSources);
      _resetLadder();
      _currentSourceIndex =
          _ladder(
            _videoSources,
            hasDirective: widget.args.extractor != null,
          ).initialPick() ??
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
      _resolvedType = widget.args.type;
      if (mounted) setState(() => _stage = _LoadingStage.loading);
      unawaited(_loadThumbnails(widget.args.thumbnails));
      await _initializeWith(
        url: source?.videoUrl ?? widget.args.movieUrl ?? '',
        headers: widget.args.headers,
        type: _typeOf(source),
        resumeAt: _jellyfinResume(
          source?.videoUrl ?? widget.args.movieUrl,
          resume,
        ),
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
    final generation = ++_mediaGeneration;
    final size = widget.args.pageSize;
    final contentUrl = widget.args.contentUrl;
    if (size <= 0 || contentUrl == null || contentUrl.isEmpty) return;

    final page = absoluteIndex ~/ size + 1;
    setState(() {
      _initializing = true;
      _stage = _LoadingStage.resolving;
      _errorMessage = null;
      _errorRaw = null;
    });

    final result = await getIt<GetEpisodesUseCase>()(
      contentUrl,
      page: page,
      size: size,
      sort: widget.args.sort,
      provider: widget.args.provider,
    );
    if (!mounted || generation != _mediaGeneration) return;

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
    if (!_window.contains(index)) {
      await _pageAcrossIfNeeded(index, resumeAt: resumeAt);
      return;
    }

    _resetForEpisode(index, keepRetryCount: keepRetryCount);
    final generation = await _tearDownForEpisode();
    if (!mounted || generation != _mediaGeneration) return;

    final ep = _episodes[index];
    final resolved = await _resolveEpisode(ep, generation);
    if (!mounted || generation != _mediaGeneration || resolved == null) return;

    await _startPlayback(
      ep,
      resolved.value,
      generation: generation,
      lang: resolved.lang,
      resumeAt: resumeAt,
    );
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
    _endHandled = false;
    _videoTrackApplied = false;
    // The next episode's first frame is a new "watching now" on Trakt; the
    // start replaces the previous one there, so no pause is needed first.
    _traktPlaying = false;
    _upNextDismissed = false;
    // And a new episode is a new question for the auto-translator: episode 4
    // may carry a subtitle in the viewer's language when episode 3 did not.
    _autoTranslateDone = false;
    setState(() {
      _initializing = true;
      _stage = _LoadingStage.resolving;
      _errorMessage = null;
      _errorRaw = null;
      _isCodecError = false;
      _window = _window.at(index);
      _panel = _SidePanel.none;
    });
  }

  /// Closes the previous stream and lets the engine settle.
  ///
  /// The delay is not decoration: disposing and immediately re-initialising a
  /// native surface is how a black frame survives into the next episode.
  Future<int> _tearDownForEpisode() async {
    // Sync is per-episode: a shift/rate tuned for the previous episode is wrong
    // here, so drop it and load whatever was saved for this one (0 / 1.0 when
    // nothing was).
    _restoreSubtitleSync();
    final generation = await _disposeController();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return generation;
  }

  /// Resolves [ep], or reports why it could not be played and returns null.
  Future<({MediaResolveEntity value, String? lang})?> _resolveEpisode(
    EpisodeEntity ep,
    int generation,
  ) async {
    final local = _localEpisode(ep);
    if (local != null) {
      _plog('playing downloaded episode ${ep.episode} from disk');
      return (
        value: MediaResolveEntity(
          videoUrl: local.url,
          type: local.type,
          headers: const {},
        ),
        lang: null,
      );
    }
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
    final prefetched = await _takePrefetched(ep, lang);
    final result = prefetched != null
        ? Success(prefetched)
        : await _resolve(
            ref: ep.mediaRef,
            provider: widget.args.provider,
            lang: lang,
          );
    _plog(
      prefetched != null
          ? 'resolve served from prefetch'
          : 'resolve completed in ${resolveSw.elapsedMilliseconds}ms',
    );
    if (!mounted || generation != _mediaGeneration) return null;

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

  /// The downloaded copy of [ep], when there is one — it plays with no
  /// network, and online it saves the resolve and the bandwidth.
  LocalVideo? _localEpisode(EpisodeEntity ep) {
    final contentUrl = widget.args.contentUrl;
    if (contentUrl == null || contentUrl.isEmpty) return null;
    if (!getIt.isRegistered<GetDownloadsUseCase>()) return null;
    return getIt<GetDownloadsUseCase>().localVideo(
      contentUrl: contentUrl,
      episodeNumber: ep.episode,
    );
  }

  /// Picks a mirror, publishes the new episode's state, and starts the stream.
  Future<void> _startPlayback(
    EpisodeEntity ep,
    MediaResolveEntity value, {
    required int generation,
    required String? lang,
    required Duration resumeAt,
  }) async {
    if (!mounted || generation != _mediaGeneration) return;
    final sources = value.videoSources;
    // `sources[0]` was taken outright here, so the remembered quality was
    // honoured on a movie and ignored on every episode of a serial — and an
    // iframe entry, which some providers put first, went straight to the
    // decoder as if it were a stream.
    final pickedIdx =
        _ladder(sources, hasDirective: value.extractor != null).initialPick() ??
        -1;
    final useSources = pickedIdx >= 0;
    final url = useSources ? sources[pickedIdx].videoUrl : value.videoUrl;
    // The picked mirror's OWN headers.
    //
    // `value.headers` is the top level, which both on-device hosts hard-code to
    // source 0's — so the moment the ladder picked anything else (a remembered
    // quality, or source 0 filtered out as unplayable) the player asked mirror
    // three for a file with mirror one's Referer and Origin. The CDN answers
    // 403 and it surfaces as a decoder failure. The manual-switch and
    // auto-retry paths already pass the source's own headers; only the first
    // play did not, which is why it looked like "some titles just don't play".
    final headers = useSources && sources[pickedIdx].headers.isNotEmpty
        ? sources[pickedIdx].headers
        : value.headers;
    // Only tracks that point at something. A source listing a track with no
    // file used to bring up the subtitle controls — style, picker — for a
    // video that has no subtitles at all.
    final subs = [
      for (final t in value.subtitles)
        if (t.file.trim().isNotEmpty) t,
    ];
    // A downloaded episode brings the subtitles kept with it.
    if (_playsDownload) {
      subs.addAll(await getIt<SubtitleSidecar>().load(_downloadId));
      if (!mounted || generation != _mediaGeneration) return;
    }

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
      _resolvedType = value.type;
    });

    unawaited(_loadThumbnails(value.thumbnails));
    await _initializeWith(
      intentGeneration: generation,
      url: url,
      headers: headers,
      type: useSources ? _typeOf(sources[pickedIdx]) : value.type,
      resumeAt: _jellyfinResume(url, resumeAt),
    );
    if (!mounted || generation != _mediaGeneration) return;
    // Host announces the new episode identity (never a video URL).
    if (_errorMessage == null) _partyEmitContent(ep, _currentLang);
    _autoPickSubtitle(subs);
  }

  /// Playing a file this app downloaded rather than a stream.
  bool get _playsDownload {
    final u = widget.args.movieUrl ?? '';
    return u.startsWith('/') ||
        u.startsWith('file:') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(u);
  }

  /// The id the download was stored under — the same the player, the
  /// episode list and the detail page build when they start one.
  String get _downloadId => DownloadRequest.videoId(
    contentUrl: widget.args.contentUrl ?? widget.args.movieUrl ?? '',
    episodeNumber: widget.args.offlineEpisodeNumber,
  );

  /// The subtitle this episode starts with.
  ///
  /// What the viewer chose on this title last time — the same label, or the
  /// same language from another server, or off — then the track the source
  /// marks as default, then one in the viewer's subtitle language. Extension
  /// sources mark none as default, so every episode started without
  /// subtitles and the language had to be picked again each time.
  void _autoPickSubtitle(List<SubtitleEntity> subs) {
    final contentUrl = widget.args.contentUrl ?? '';
    final remembered = contentUrl.isEmpty
        ? null
        : _titlePrefs.subtitleFor(widget.args.provider, contentUrl);
    _pendingEmbeddedChoice = null;
    if (remembered == TitlePrefsStore.subtitleOff) {
      // Off stays off, the stream's own tracks included.
      _pendingEmbeddedChoice = TitlePrefsStore.subtitleOff;
      return;
    }
    if (remembered != null &&
        remembered.startsWith(TitlePrefsStore.embeddedSubtitle)) {
      _pendingEmbeddedChoice = remembered.substring(
        TitlePrefsStore.embeddedSubtitle.length,
      );
      return;
    }
    if (subs.isEmpty) return;
    var pick = -1;
    if (remembered != null) {
      pick = subs.indexWhere((s) => s.label == remembered);
      if (pick < 0) {
        final lang = SubtitleAutoTranslate.languageOf(remembered);
        pick = subs.indexWhere(
          (s) => SubtitleAutoTranslate.languageOf(s.label) == lang,
        );
      }
    }
    if (pick < 0) pick = subs.indexWhere((s) => s.isDefault);
    if (pick < 0) {
      final wanted = _hive.getSubtitleTranslateLang().toLowerCase();
      pick = subs.indexWhere(
        (s) => SubtitleAutoTranslate.labelMatchesLanguage(s.label, wanted),
      );
    }
    if (pick >= 0) unawaited(_loadSubtitle(pick, remember: false));
  }

  /// Applies [_pendingEmbeddedChoice] once the stream's tracks are listed.
  void _applyEmbeddedSubtitleChoice() {
    final choice = _pendingEmbeddedChoice;
    final c = _controller;
    if (choice == null || c == null || !c.supportsSubtitleTracks) return;
    final tracks = c.subtitleTracks;
    if (tracks.isEmpty) return;
    _pendingEmbeddedChoice = null;
    if (choice == TitlePrefsStore.subtitleOff) {
      if (c.activeSubtitleTrackId != null) {
        unawaited(c.setSubtitleTrack(PlayerSubtitleTrack.off));
      }
      return;
    }
    // An external track the viewer picked since wins over the memory.
    if (_activeSubtitleIndex != -1) return;
    final lang = SubtitleAutoTranslate.languageOf(choice);
    final match =
        tracks.where((t) => t.label == choice).firstOrNull ??
        tracks
            .where((t) => SubtitleAutoTranslate.languageOf(t.label) == lang)
            .firstOrNull;
    if (match != null && match.id != c.activeSubtitleTrackId) {
      unawaited(c.setSubtitleTrack(match.id));
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
  }) => SourceLadder(
    sources: sources,
    hasDirective: hasDirective,
    rememberedQuality: SourceLadder.rememberedQualityFor(
      _titlePrefs,
      provider: widget.args.provider,
      contentUrl: widget.args.contentUrl ?? '',
    ),
    avoidCodec: _decoderAvoidCodec,
    triedUrls: _triedSourceUrls,
    preferredHeight: _qualityPreference,
  );

  /// What to start on: this session's pick, then this title's, then the
  /// standing setting.
  int get _qualityPreference {
    final manual = _manualHeight;
    if (manual != null) return manual;
    final contentUrl = widget.args.contentUrl ?? '';
    final remembered = contentUrl.isEmpty
        ? null
        : _titlePrefs.heightChoiceFor(widget.args.provider, contentUrl);
    return remembered ?? _hive.preferredQuality;
  }

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
    if (_currentSourceIndex >= 0 &&
        _currentSourceIndex < _videoSources.length) {
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

  Future<void> _switchQuality(
    VideoSourceEntity source, {
    bool remember = true,
    bool pickedHeight = true,
  }) async {
    // Which ROW, not which label. Two servers may both call themselves
    // "1080p", and matching on the label made the second one impossible to
    // pick: it read as the one already playing and the tap did nothing.
    var idx = _videoSources.indexOf(source);
    if (idx < 0) {
      idx = _videoSources.indexWhere((s) => s.videoUrl == source.videoUrl);
    }
    if (idx >= 0 && idx == _currentSourceIndex) {
      setState(() => _panel = _SidePanel.none);
      return;
    }
    // Remembered for this title. Plenty of shows only play on their third
    // mirror, and re-picking it every episode is the kind of chore that reads
    // as the app not working. The height is left alone on a server switch:
    // that lands on the server's first row, and recording it would quietly
    // unpin the quality.
    final height =
        source.height ?? VideoOptionGroups.resolutionOf(source.quality) ?? 0;
    if (remember && pickedHeight) _manualHeight = height;
    if (remember) {
      unawaited(
        _titlePrefs.rememberQuality(
          widget.args.provider,
          widget.args.contentUrl ?? '',
          source.quality,
        ),
      );
    }
    if (remember && pickedHeight) {
      unawaited(
        _titlePrefs.rememberHeight(
          widget.args.provider,
          widget.args.contentUrl ?? '',
          height,
        ),
      );
    }
    final keepPosition = _controller?.value.position ?? Duration.zero;
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
      _errorRaw = null;
      _isCodecError = false;
      _currentQuality = source.quality;
      _currentSourceIndex = idx >= 0 ? idx : _currentSourceIndex;
      _panel = _SidePanel.none;
    });
    final generation = await _disposeController();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted || generation != _mediaGeneration) return;
    await _initializeWith(
      intentGeneration: generation,
      url: source.videoUrl,
      // The new mirror's own headers when it has any: the previous one's
      // Referer and cookies belong to a different host.
      headers: source.headers.isNotEmpty
          ? source.headers
          : (_headers.isNotEmpty ? _headers : widget.args.headers),
      type: _typeOf(source),
      resumeAt: keepPosition,
    );
  }

  /// The source this url belongs to, or null when nothing here claims it.
  ///
  /// Exact match first, because that is the common case and the only one that
  /// is certain. Then the current index, if it happens to point at something
  /// that wants a proxy — a sniffed or derived url is a different string for
  /// the same stream. Then, and only for a source that declares a proxy, a HOST
  /// match: these transforms are defined per CDN host, so a url on the host the
  /// config names is a url the config is about.
  ///
  /// Deliberately never a blind fallback to source 0. Sending an unrelated
  /// stream through another source's signing transform would produce a
  /// confidently wrong request rather than an honest direct one.
  VideoSourceEntity? _sourceForUrl(String url) {
    if (_videoSources.isEmpty) return null;
    for (final s in _videoSources) {
      if (s.videoUrl == url) return s;
    }
    if (_currentSourceIndex >= 0 &&
        _currentSourceIndex < _videoSources.length) {
      final current = _videoSources[_currentSourceIndex];
      if (current.useLocalProxy) return current;
    }
    final host = Uri.tryParse(url)?.host;
    if (host == null || host.isEmpty) return null;
    for (final s in _videoSources) {
      if (!s.useLocalProxy) continue;
      if (Uri.tryParse(s.videoUrl)?.host == host) return s;
    }
    return null;
  }

  Future<_ProxiedTarget?> _maybeRouteThroughLocalProxy({
    required String url,
    required Map<String, String> headers,
  }) async {
    // Found by URL, with the index only as a hint.
    //
    // This used to key entirely off `_currentSourceIndex` and then refuse to
    // proxy unless that source's url was byte-identical to the one about to
    // play. Both are fragile in a way that fails silently and unplayably: the
    // index is -1 until a ladder pick lands, it is not updated when a master
    // playlist is expanded into per-quality rows mid-play, and a mirror
    // switch, a retry or a sniffed url all arrive here with the list in a
    // state the index no longer describes.
    //
    // For an ordinary source, being wrong there costs nothing — the direct url
    // plays. For a source whose CDN only answers a signed, transformed request
    // it costs everything: uzmovi's host 301s every unsigned request to its own
    // home page, so the player is handed HTML and reports "failed to open" with
    // a url that looks perfectly reasonable.
    //
    // The url is the one thing that is true at this point, so it is what the
    // lookup uses.
    final source = _sourceForUrl(url);
    if (source == null) {
      _plog(
        'local proxy skipped: no source carries this url '
        '(idx=$_currentSourceIndex, count=${_videoSources.length}) — direct URL',
        level: LogLevel.warn,
      );
      return null;
    }
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
    final upstreamHeaders = source.headers.isNotEmpty
        ? source.headers
        : headers;
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
      _plog(
        'local proxy register failed: $e — using direct url',
        level: LogLevel.warn,
      );
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
      // The plain client: this is a CDN, and the app's own Dio pins the
      // backend's certificate chain — against any other host the handshake
      // fails and every rewrite looked "rejected".
      final res = await ExternalDio.instance.get<String>(
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
      _plog(
        'rewrite check failed: $e — playing the sniffed url',
        level: LogLevel.warn,
      );
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

    // Shared with the downloader, which needs the same ranking to stop saving
    // the lowest rendition of a stream the player is showing at 1080p.
    final variants = parseHlsVariants(body, base);
    if (variants.isEmpty) return;

    // One entry per height: a master often carries the same resolution twice at
    // different bitrates, which would show the sheet two rows both `1080p`.
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

    _variantUrls.addAll(expanded.skip(1).map((e) => e.videoUrl));
    _plog(
      'master playlist -> ${expanded.length - 1} qualities '
      '(${expanded.skip(1).map((e) => e.quality).join(", ")})',
    );
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
    int? intentGeneration,
  }) async {
    final generation = intentGeneration ?? ++_mediaGeneration;
    if (!mounted || generation != _mediaGeneration) return;
    // Remembered before anything rewrites it — see [_playSourceUrl].
    _playSourceUrl = url;
    _playSourceHeaders = headers;
    var effUrl = url;
    var effHeaders = headers;
    var effType = type;

    // Only when the server sent a directive — no provider check, no url
    // pattern-matching. See `_extractorConfig`.
    final cfg = _extractorConfig;
    if (cfg != null && url.isNotEmpty && !_variantUrls.contains(url)) {
      _plog(
        'webview sniff: host=${cfg.hostPattern} patterns=${cfg.urlPatterns}',
      );
      final sw = Stopwatch()..start();
      final sniffed = await getIt<WebViewStreamExtractor>().extract(
        pageUrl: url,
        config: cfg,
        pageHeaders: headers,
      );
      if (!mounted || generation != _mediaGeneration) return;
      if (sniffed != null) {
        effUrl = sniffed.url;
        // Sniffed headers win: they are the ones the page actually sent, and
        // the CDN gates on exactly those.
        effHeaders = {...headers, ...sniffed.headers};
        effType = sniffed.playType;
        _plog('sniff ok in ${sw.elapsedMilliseconds}ms -> $effUrl');
        effUrl = await _applyRewrite(cfg.rewrite, effUrl, effHeaders);
        if (!mounted || generation != _mediaGeneration) return;
      } else {
        // The url in hand is the embed PAGE. Handing that to the player used to
        // cost two doomed retries and a minute of spinner before an error that
        // blamed the format — the page is HTML, so of course no extractor reads
        // it. Say what actually happened, and offer the browser, which is where
        // a player this protected does work.
        _plog(
          'sniff found no stream in ${sw.elapsedMilliseconds}ms',
          level: LogLevel.warn,
        );
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

    // Before playback, not after: the sheet is built from `_videoSources`, and
    // a viewer who opens it during the first ten seconds should already find
    // the renditions there.
    final pinned = await _maybeExpandQualities(
      effUrl,
      effHeaders,
      effType,
      generation,
    );
    if (!mounted || generation != _mediaGeneration) return;
    // Straight onto the preferred rendition rather than starting the master
    // and switching a second later: one load, and the resume point holds.
    if (pinned != null) {
      final idx = _videoSources.indexOf(pinned);
      setState(() {
        if (idx >= 0) _currentSourceIndex = idx;
        _currentQuality = pinned.quality;
      });
      effUrl = pinned.videoUrl;
      // A retry replays this; the master would come back as Auto under the
      // pinned row's label.
      _playSourceUrl = effUrl;
      _playSourceHeaders = effHeaders;
    }

    await _initializeResolved(
      generation: generation,
      url: effUrl,
      headers: effHeaders,
      type: effType,
      resumeAt: resumeAt,
      party: party,
    );
  }

  /// Gives the current server real quality rows, parsed out of its own master
  /// playlist.
  ///
  /// [_expandMasterPlaylist] already did this, but from one place only: inside
  /// [_applyRewrite], for a provider carrying a rewrite rule that verifies, and
  /// only when the whole source list was a single entry. Most providers have no
  /// such rule. vidapi returns three HLS masters and labels them `Server 1..3`,
  /// so the sheet listed three servers, the renditions inside each were never
  /// surfaced, and nothing but the connection speed decided between 480p and
  /// 1080p. That is the "no manual quality control" report.
  ///
  /// The current entry is left exactly as it is and the renditions are inserted
  /// after it — it keeps its url, its headers and its proxy settings, so it
  /// still resolves the way it did, and it goes on being the adaptive choice.
  /// Only the server being played is fetched; the others are expanded if and
  /// when they are switched to.
  ///
  /// Costs one GET, skipped whenever there is already something to choose
  /// from. Failure is silent: this widens a menu, it does not gate playback.
  Future<VideoSourceEntity?> _maybeExpandQualities(
    String url,
    Map<String, String> headers,
    String? type,
    int generation,
  ) async {
    final idx = _currentSourceIndex;
    if (idx < 0 || idx >= _videoSources.length) return null;
    final parent = _videoSources[idx];
    // The guard used to be "this url was expanded once this session", so a
    // re-resolve that brought the same master back — an audio-language
    // switch, a retry — replaced the list and never got its rows again.
    if (!QualityPreference.shouldExpand(
      label: parent.quality,
      url: url,
      type: type,
      siblingLabels: [
        for (final s in _videoSources)
          if (s.height != null) s.quality,
      ],
    )) {
      return null;
    }
    // In flight: two expansions of one master at once would insert twice.
    if (!_expandedMasters.add(url)) return null;
    try {
      return await _expandQualities(
        parent,
        idx,
        url,
        headers,
        type,
        generation,
      );
    } finally {
      _expandedMasters.remove(url);
    }
  }

  /// Returns the row the viewer's preference pins, or null to stay on the
  /// adaptive entry.
  Future<VideoSourceEntity?> _expandQualities(
    VideoSourceEntity parent,
    int idx,
    String url,
    Map<String, String> headers,
    String? type,
    int generation,
  ) async {
    final kind = type?.toLowerCase();
    if (kind == 'dash' || url.toLowerCase().contains('.mpd')) {
      await _expandDash(parent, idx, url, headers, generation);
      return null;
    }

    final base = Uri.tryParse(url);
    if (base == null) return null;

    String body;
    try {
      // The plain client, for the same reason as in [_applyRewrite]: a master
      // playlist lives on a CDN, not behind the backend's pinned chain.
      final res = await ExternalDio.instance.get<String>(
        url,
        options: Options(
          headers: headers,
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
          receiveTimeout: const Duration(seconds: 8),
          extra: const {'skipAuthInterceptor': true},
        ),
      );
      if (res.statusCode != 200) return null;
      body = res.data ?? '';
    } catch (_) {
      // A master that will not load is the player's problem to report, not
      // this one's — it is about to request the same url.
      return null;
    }
    if (!body.trimLeft().startsWith('#EXTM3U')) return null;

    // Shared with the downloader, so the file saved matches the rendition the
    // sheet offered.
    final variants = parseHlsVariants(body, base);

    // One row per height: a master often carries the same resolution twice at
    // different bitrates, which would list `1080p` twice.
    final seen = <int>{};
    final rows = <VideoSourceEntity>[
      for (final v in variants)
        if (v.height > 0 && seen.add(v.height))
          VideoSourceEntity(
            quality: '${parent.quality} · ${v.height}p',
            videoUrl: v.url,
            isDefault: false,
            accessible: parent.accessible,
            height: v.height,
            type: parent.type ?? 'hls',
            // The headers the master was just fetched with: after a sniff
            // those carry what the CDN gates on, which the parent's own
            // page headers do not.
            headers: headers.isNotEmpty ? headers : parent.headers,
            useLocalProxy: parent.useLocalProxy,
            localProxy: parent.localProxy,
            requestTransform: parent.requestTransform,
            drm: parent.drm,
          ),
    ];
    return _insertQualityRows(parent, idx, rows, generation, 'master playlist');
  }

  /// A DASH stream's renditions as quality rows.
  ///
  /// Each row is the same manifest, served by the local proxy with only that
  /// video Representation left in it — the player cannot then pick another.
  /// Neither engine here exposes DASH track selection, so this is the one
  /// way a DASH stream gets a manual quality.
  Future<void> _expandDash(
    VideoSourceEntity parent,
    int idx,
    String url,
    Map<String, String> headers,
    int generation,
  ) async {
    String body;
    try {
      final res = await ExternalDio.instance.get<String>(
        url,
        options: Options(
          headers: headers,
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
          receiveTimeout: const Duration(seconds: 8),
          extra: const {'skipAuthInterceptor': true},
        ),
      );
      if (res.statusCode != 200) return;
      body = res.data ?? '';
    } catch (_) {
      return;
    }
    if (!DashManifest.looksLikeMpd(body)) return;
    final reps = DashManifest.videoRepresentations(body);
    if (reps.length < 2) return;
    final upstream = parent.videoUrl;
    final upHeaders = parent.headers.isNotEmpty ? parent.headers : headers;
    final rows = <VideoSourceEntity>[];
    for (final r in reps) {
      try {
        final proxied = await getIt<LocalHlsProxy>().register(
          upstreamUrl: upstream,
          headers: upHeaders,
          localProxy: parent.localProxy,
          requestTransform: parent.requestTransform,
          dashRepresentation: r.id,
        );
        rows.add(
          VideoSourceEntity(
            quality: '${parent.quality} · ${r.height}p',
            videoUrl: proxied,
            isDefault: false,
            accessible: parent.accessible,
            height: r.height,
            type: 'dash',
            // The proxy carries the stream's headers upstream.
            headers: const {},
            useLocalProxy: false,
            drm: parent.drm,
          ),
        );
      } catch (_) {
        return;
      }
    }
    await _insertQualityRows(parent, idx, rows, generation, 'dash manifest');
  }

  /// Inserts the rows after the adaptive entry and returns the one the
  /// viewer's preferred quality pins, if any.
  Future<VideoSourceEntity?> _insertQualityRows(
    VideoSourceEntity parent,
    int idx,
    List<VideoSourceEntity> rows,
    int generation,
    String from,
  ) async {
    // One rendition beside the adaptive entry is not a choice, and a quality
    // control that opens onto a single row reads as broken — the same rule the
    // engine track list follows.
    if (rows.length < 2) return null;

    _plog(
      '$from -> ${rows.length} qualities for '
      '"${parent.quality}" (${rows.map((e) => e.height).join(", ")})',
    );
    if (!mounted || generation != _mediaGeneration) return null;
    if (_currentSourceIndex != idx || !identical(_videoSources[idx], parent)) {
      return null;
    }
    _variantUrls.addAll(rows.map((r) => r.videoUrl));
    setState(() {
      _videoSources = [
        ..._videoSources.take(idx + 1),
        ...rows,
        ..._videoSources.skip(idx + 1),
      ];
    });
    // The rows did not exist when the episode chose its source, so without
    // this a pick of "Server · 720p" fell back to Auto on every next episode.
    final want = QualityPreference.pick(
      rows.map((r) => r.height ?? 0),
      _qualityPreference,
    );
    if (want == null) return null;
    return rows.where((r) => r.height == want).firstOrNull;
  }

  /// On libmpv the renditions are the engine's own tracks: the preferred
  /// height is picked from them once they are listed.
  void _applyRememberedVideoTrack() {
    if (_videoTrackApplied) return;
    final c = _controller;
    if (c == null || !c.supportsVideoTracks) return;
    final tracks = c.videoTracks;
    if (tracks.isEmpty) return;
    _videoTrackApplied = true;
    final want = QualityPreference.pick(
      tracks.where((t) => !t.isAuto).map((t) => t.height ?? 0),
      _qualityPreference,
    );
    if (want == null) return;
    final match = tracks
        .where((t) => !t.isAuto && t.height == want)
        .firstOrNull;
    if (match != null && match.id != c.activeVideoTrackId) {
      unawaited(c.setVideoTrack(match.id));
    }
  }

  Future<void> _initializeResolved({
    required int generation,
    required String url,
    required Map<String, String> headers,
    required String? type,
    Duration resumeAt = Duration.zero,
    PartyPlayback? party,
  }) async {
    if (!mounted || generation != _mediaGeneration) return;
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
      if (!mounted || generation != _mediaGeneration) return;
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
    final isDash =
        type?.trim().toLowerCase() == 'dash' ||
        url.toLowerCase().contains('.mpd');
    _isHls = isHls;

    final proxied = !isLocal && isHls
        ? await _maybeRouteThroughLocalProxy(url: url, headers: headers)
        : null;
    if (!mounted || generation != _mediaGeneration) return;
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

    // Engine = External player. Sozo still does the hard part — extraction,
    // header-gated proxying, picking the quality — and then hands the resolved
    // URL to VLC / MX Player. That happens HERE, before a controller exists:
    // it used to happen after `initialize()`, which opened the stream in-app
    // first — network, a decoder, and on some sources the one use of a
    // single-use token — only to pause it again, the opposite of what the note
    // in media_controller promises. Resume position is NOT carried across: the
    // intent has no standard extra for it, so the external app starts from zero.
    if (ExternalPlayer.isSupported &&
        resolvePlayerEngine() == PlayerEngine.external) {
      _videoUrl = effectiveUrl;
      _headers = isLocal
          ? const {}
          : _mergedStreamHeaders(Uri.parse(effectiveUrl), effectiveHeaders);
      _mediaType = type;
      _plog('external engine — handing off to a third-party player');
      setState(() {
        _initializing = false;
        _errorMessage = null;
        _errorRaw = null;
        _isCodecError = false;
      });
      await _handOffToExternalPlayer();
      return;
    }

    PlayerController controller;
    if (isLocal && isHls) {
      final fileUri = isFileUri
          ? Uri.parse(effectiveUrl)
          : Uri.file(effectiveUrl);
      controller = PlayerController.networkUrl(
        fileUri,
        preferPlatform: _preferPlatformPlayer,
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
        preferPlatform: _preferPlatformPlayer,
        videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: false),
      );
      _headers = const {};
    } else {
      final uri = Uri.parse(effectiveUrl);
      final mergedHeaders = await _streamHeaders(uri, effectiveHeaders);
      if (!mounted || generation != _mediaGeneration) return;

      _plog('provider: ${widget.args.provider}');
      _plog('headers (${mergedHeaders.length}):');
      mergedHeaders.forEach((k, v) {
        _plog('  $k: $v');
      });

      // The source being played decides whether this stream is encrypted, so
      // it is read here rather than carried on the page: switching quality or
      // mirror can move between an encrypted rendition and a clear one, and the
      // backend has to follow.
      final drm =
          _currentSourceIndex >= 0 && _currentSourceIndex < _videoSources.length
          ? _videoSources[_currentSourceIndex].drm
          : null;
      if (drm != null) _plog('drm: $drm');

      controller = PlayerController.networkUrl(
        uri,
        httpHeaders: mergedHeaders,
        preferPlatform: _preferPlatformPlayer,
        formatHint: isHls
            ? VideoFormat.hls
            : isDash
            ? VideoFormat.dash
            : null,
        videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: false),
        drm: drm,
      );
      _headers = mergedHeaders;
    }
    _controller = controller;
    _videoUrl = effectiveUrl;
    _mediaType = type;
    // Known BEFORE the first frame, not after it. A channel that is down at the
    // moment you open it fails during initialize(), and the error path has to
    // already know it is looking at a broadcast — otherwise the one case that
    // most needs reconnecting is the one that gets a dead end.
    if (type == 'live' || widget.args.type == 'live') _isLive = true;

    try {
      await controller.initialize();
      _plog('initialize completed in ${stopwatch.elapsedMilliseconds}ms');
      if (!mounted ||
          generation != _mediaGeneration ||
          !identical(_controller, controller)) {
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
      _isLive =
          _mediaType == 'live' ||
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

      // Preview decoding starts only when the viewer scrubs. Eager warming
      // opens a second video decoder while a high-resolution stream starts.
      controller.addListener(_onMajorChange);
      await controller.setLooping(false);
      if (!mounted || generation != _mediaGeneration) return;
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
        if (!mounted || generation != _mediaGeneration) return;
        if (!_isLive) {
          final expected = party.expectedPositionAt(DateTime.now());
          if (expected > 0) {
            await controller.seekTo(
              Duration(milliseconds: (expected * 1000).round()),
            );
          }
        }
        if (!mounted || generation != _mediaGeneration) return;
        if (party.isPlaying) {
          await controller.play();
        }
      } else {
        await controller.setPlaybackSpeed(_playbackSpeed);
        if (!mounted || generation != _mediaGeneration) return;
        if (resumeAt > Duration.zero && !_isLive) {
          await controller.seekTo(resumeAt);
        }
        if (!mounted || generation != _mediaGeneration) return;
        // Paused, if that is what was asked for — but only for the episode
        // somebody opened. An auto-advance is already playing by definition:
        // the preference is about the app starting a stream on its own when a
        // page is opened, and refusing to continue a run somebody is already
        // watching would be a different setting entirely.
        if (!_hive.startPaused || _autoAdvanced) {
          await controller.play();
        }
      }
      _plog('play started — total ${stopwatch.elapsedMilliseconds}ms');
      _schedulePreviewWarm(generation);
      // Against the source that SERVED this, which is the whole point.
      //
      // Searching well and playing are different skills, and until now the only
      // evidence the source order was built on came from the search: a source
      // that answers in 200ms and then cannot produce a stream sat ahead of one
      // that takes a second and always plays. This is the first moment anything
      // knows a stream actually reached a frame.
      //
      // Here rather than at resolve time: a resolved url is not a playing one.
      // A dead mirror, a 403 on the first segment and a codec the device cannot
      // decode all resolve perfectly and never play.
      //
      // `widget.args.provider` is the serving source without qualification:
      // switching source mid-episode builds a whole new PlayerArgs around the
      // new provider rather than swapping a url underneath this one.
      unawaited(SourceHealthStore().recordPlay(widget.args.provider));
      // Guarded, because everything between initialize() and here is awaited —
      // a seek, a speed change, the play itself — and a slow source spends
      // seconds in that stretch. Seconds spent staring at a spinner is exactly
      // when someone backs out, and coming back to a disposed State throws.
      if (!mounted || generation != _mediaGeneration) return;
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
        _errorRaw = null;
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
      _plog(
        'platform exception ${e.code}: ${e.message}',
        level: LogLevel.error,
      );
      if (!mounted || generation != _mediaGeneration) return;
      final raw = e.message ?? '';
      String msg;
      if (e.code == 'channel-error') {
        msg = PlaybackFaultKind.engineUnavailable.messageKey.tr();
      } else if (_isDecoderError(raw)) {
        // The codec is the likeliest culprit, so siblings encoded the same way
        // go to the back of the ladder rather than being tried in turn.
        _decoderAvoidCodec =
            _currentSourceIndex >= 0 &&
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
        _plog(
          'recoverable error, retrying (attempt ${_retryAttempts + 1})',
          level: LogLevel.warn,
        );
        _retryAttempts++;
        _lifetimeRetries++;
        _autoRetrying = true;
        _autoRetry();
        return;
      } else {
        // A refusal is not the end of the walk.
        //
        // `_isRecoverableError` above means "re-opening THIS url might help".
        // Everything it rejects — a 403, a 404, a dead host — lands here, and
        // that is PRECISELY the case where another mirror is the answer: the
        // file is gone from this server, not from all of them. The branch
        // simply printed the error, so a title with five mirrors gave up on
        // the first one that 404'd with four untried.
        //
        // [RetryPolicy] already encodes this, with tests. It had no caller at
        // all — the page hand-rolled the same decision and got the last case
        // wrong. Marked tried first, because `_hasUntriedSource` asks what is
        // LEFT and the mirror that just failed is not.
        if (!_isLive) _markCurrentTried();
        final action = RetryPolicy.decide(
          message: raw,
          isLive: _isLive,
          attempts: _retryAttempts,
          lifetime: _lifetimeRetries,
          hasUntriedSource: _hasUntriedSource,
        );
        if (action == RetryAction.nextSource && _hasUntriedSource) {
          _plog('refused here, trying another source', level: LogLevel.warn);
          _retryAttempts++;
          _lifetimeRetries++;
          _autoRetrying = true;
          _autoRetry();
          return;
        }
        msg = raw.isEmpty
            ? PlaybackFaultKind.unknown.messageKey.tr()
            : _humanizeError(raw);
      }
      setState(() {
        _initializing = false;
        _errorMessage = msg;
        _errorRaw = raw;
      });
    } catch (e) {
      _plog('init threw: $e', level: LogLevel.error);
      if (!mounted || generation != _mediaGeneration) return;
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

  bool _isRecoverableError(String msg) => RetryPolicy.isRecoverableError(msg);

  /// Keeps the screen awake while the video is running, and only then.
  ///
  /// The hold used to be taken when the player opened and dropped when it
  /// closed, so a paused episode left on screen held the phone awake until the
  /// battery gave out — pause, put it down, come back to a hot phone. Nothing
  /// is watching a paused frame.
  ///
  /// Idempotent: WakelockHolds is a set, so repeating the same state is free
  /// and this can be called from a listener that fires on every tick.
  void _syncWakelock(bool playing) {
    final want = playing && _hive.keepScreenOn;
    if (want == _wakelockHeld) return;
    _wakelockHeld = want;
    if (want) {
      WakelockHolds.acquire(this);
    } else {
      WakelockHolds.release(this);
    }
  }

  void _onMajorChange() {
    final c = _controller;
    if (c == null) return;
    final v = c.value;

    _syncWakelock(v.isPlaying);
    _syncTraktScrobble(v.isPlaying);
    _applyEmbeddedSubtitleChoice();
    _applyRememberedVideoTrack();

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
          _decoderAvoidCodec =
              _currentSourceIndex >= 0 &&
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
        _stopHistorySaves();
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
      _maybePrefetchNext(v.position, v.duration);

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
            !_upNextDismissed &&
            _hive.autoPlayNextEpisode &&
            widget.args.isSerial &&
            _hasNextEpisode) {
          _saveHistoryForNextEpisode();
          // Marks the next load as a continuation rather than an opening, so
          // "start paused" does not stop a run that is already going.
          _autoAdvanced = true;
          _loadEpisode(_episodeIndex + 1);
          return;
        }
        if (!_endHandled) {
          _endHandled = true;
          _recordFinishedWithoutAdvancing();
        }
        if (_sleepAtEpisodeEnd) unawaited(_fireSleepTimer());
      }
    }

    if (changed && mounted) setState(() {});
  }

  /// What history says once an episode has played out and nothing advanced.
  ///
  /// This used to call `_history.remove(contentUrl)` for everything, on every
  /// tick of the last two seconds. For a film that is right — finished, so it
  /// leaves Continue Watching. For a series it did nothing useful: episode rows
  /// are keyed per episode, so the finished one stayed at 99% and Continue
  /// kept offering to resume the episode just watched. Now a series moves its
  /// resume point to the next episode, the same row auto-advance would have
  /// written, and the last episode of a show is left alone — an ongoing show
  /// gets new episodes, and its row is how the viewer finds them.
  void _recordFinishedWithoutAdvancing() {
    final url = widget.args.contentUrl;
    if (url == null || url.isEmpty) return;
    // A downloaded episode of a series is not a finished film: its row is the
    // episode's, and the series row it would remove is not this file's to drop.
    if (widget.args.offlineEpisodeNumber != null) return;
    if (!widget.args.isSerial) {
      unawaited(_history.remove(url));
      return;
    }
    if (_hasNextEpisode) _saveHistoryForNextEpisode();
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
    final intent = ++_mediaGeneration;
    final attempt = _lifetimeRetries;
    _plog('live stream dropped — reconnecting (attempt $attempt)');

    setState(() {
      _stage = _LoadingStage.loading;
      _errorMessage = null;
      _errorRaw = null;
      _isCodecError = false;
    });

    await Future<void>.delayed(_liveRetryBackoff(attempt - 1));
    if (!mounted || intent != _mediaGeneration) return;

    final url = _videoUrl;
    if (url == null) {
      _autoRetrying = false;
      return;
    }
    final generation = await _disposeController();
    if (!mounted || generation != _mediaGeneration) return;
    await _initializeWith(
      intentGeneration: generation,
      url: url,
      headers: _headers,
      type: _mediaType,
    );
    if (mounted && generation == _mediaGeneration) _autoRetrying = false;
  }

  Future<void> _autoRetry() async {
    if (!mounted) return;

    // Where they were, read before anything tears the controller down.
    //
    // A recoverable error is usually a connection that went away — a lift, a
    // tunnel, a handover — and the viewer has not asked to start again. Every
    // branch below re-initialises, and until this was captured all three did
    // it at zero: a drop thirty-eight minutes into an episode restarted it,
    // and then the five-second save wrote 0:05 over the position on disk and
    // `dispose`'s sync pushed that to every other device. Quality and language
    // switches have always carried the position through; a retry is the same
    // move for a worse reason.
    final keepPosition = _isLive
        ? Duration.zero
        : (_controller?.value.position ?? Duration.zero);

    // Every remaining mirror, in ladder order — not `+ 1` once and done.
    _markCurrentTried();
    final nextIdx = _ladder(
      _videoSources,
      hasDirective: _extractorConfig != null,
    ).next();
    if (nextIdx != null) {
      final next = _videoSources[nextIdx];
      setState(() {
        _initializing = true;
        _stage = _LoadingStage.loading;
        _errorMessage = null;
        _errorRaw = null;
        _isCodecError = false;
        _currentSourceIndex = nextIdx;
        _currentQuality = next.quality;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('player.switching_to'.tr(args: [next.quality])),
            backgroundColor: Colors.black87,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      final generation = await _disposeController();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted || generation != _mediaGeneration) return;
      await _initializeWith(
        intentGeneration: generation,
        url: next.videoUrl,
        headers: next.headers.isNotEmpty
            ? next.headers
            : (_headers.isNotEmpty ? _headers : widget.args.headers),
        type: _typeOf(next),
        resumeAt: keepPosition,
      );
      if (mounted && generation == _mediaGeneration) _autoRetrying = false;
      return;
    }

    setState(() {
      _initializing = true;
      _stage = widget.args.isSerial
          ? _LoadingStage.resolving
          : _LoadingStage.loading;
      _errorMessage = null;
      _errorRaw = null;
      _isCodecError = false;
    });
    final generation = await _disposeController();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted || generation != _mediaGeneration) return;
    if (widget.args.isSerial) {
      _autoRetrying = false;
      await _loadEpisode(
        _episodeIndex,
        keepRetryCount: true,
        resumeAt: keepPosition,
      );
      return;
    } else if (_videoUrl != null) {
      if (!mounted || generation != _mediaGeneration) return;
      await _initializeWith(
        intentGeneration: generation,
        // Same reason as the manual retry: re-run what produced the stream,
        // not the stream. See [_playSourceUrl].
        url: _playSourceUrl ?? _videoUrl!,
        headers: _playSourceUrl != null ? _playSourceHeaders : _headers,
        type: _mediaType,
        resumeAt: keepPosition,
      );
    } else {
      _autoRetrying = false;
      await _bootstrap();
      return;
    }
    if (mounted && generation == _mediaGeneration) _autoRetrying = false;
  }

  Future<int> _disposeController() async {
    _jellyfinStop();
    final generation = ++_mediaGeneration;
    _hideTimer?.cancel();
    final c = _controller;
    _controller = null;
    unawaited(FramePreviewService.close());
    if (c != null) {
      c.removeListener(_onMajorChange);
      try {
        await c.pause();
      } catch (_) {}
      await c.dispose();
    }
    if (generation != _mediaGeneration) return generation;
    _wasPlaying = false;
    _wasBuffering = false;
    _wasInitialized = false;
    _lastError = null;
    return generation;
  }

  String _episodeTitle() {
    if (!widget.args.isSerial) {
      final offline = widget.args.offlineEpisodeNumber;
      if (offline == null) return widget.args.title;
      final label = widget.args.offlineEpisodeLabel?.trim() ?? '';
      return '${widget.args.title} · ${label.isEmpty ? 'EP $offline' : label}';
    }
    final ep = _episodes[_episodeIndex];
    final fallback = 'Episode ${ep.episode}';
    final label = ep.label.trim().isEmpty ? fallback : ep.label;
    return '${widget.args.title} · $label';
  }

  Future<void> _playWithSystemPlayer() async {
    final url = _videoUrl;
    if (url == null || _preferPlatformPlayer) return;
    final headers = Map<String, String>.of(_headers);
    final type = _mediaType;
    final position = _controller?.value.position ?? Duration.zero;
    setState(() {
      _preferPlatformPlayer = true;
      _initializing = true;
      _stage = _LoadingStage.loading;
      _errorMessage = null;
      _errorRaw = null;
      _isCodecError = false;
    });
    final generation = await _disposeController();
    if (!mounted || generation != _mediaGeneration) return;
    await _initializeWith(
      url: url,
      headers: headers,
      type: type,
      resumeAt: position,
      intentGeneration: generation,
    );
  }

  Future<void> _retry() async {
    // Read the position before the reload tears the controller down: a manual
    // retry is nearly always a mid-episode drop-out, and reloading from zero
    // would throw away however far the viewer had got. A live stream has no
    // meaningful position to come back to, so it starts at the edge.
    final keepPosition = _isLive
        ? Duration.zero
        : (_controller?.value.position ?? Duration.zero);
    if (widget.args.isSerial) {
      await _loadEpisode(_episodeIndex, resumeAt: keepPosition);
    } else if (_videoUrl != null) {
      setState(() {
        _initializing = true;
        _stage = _LoadingStage.loading;
        _errorMessage = null;
        _errorRaw = null;
        _isCodecError = false;
      });
      final generation = await _disposeController();
      if (!mounted || generation != _mediaGeneration) return;
      await _initializeWith(
        intentGeneration: generation,
        // The url that PRODUCED the stream, not the stream — see
        // [_playSourceUrl]. Retrying with `_videoUrl` re-fed a sniffed file
        // back into the sniffer.
        url: _playSourceUrl ?? _videoUrl!,
        headers: _playSourceUrl != null ? _playSourceHeaders : _headers,
        type: _mediaType,
        resumeAt: keepPosition,
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
      final response = await ExternalDio.instance.get<String>(
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

  /// Starts filling the seek-preview grid once playback has settled.
  ///
  /// Eight seconds in, not at once: the first seconds are when playback is
  /// fighting for bandwidth to fill its buffer, and a scrub that early is
  /// rare. Skipped when the source has a storyboard (its sprites already are
  /// the grid), for live streams, and for anything shorter than a minute.
  void _schedulePreviewWarm(int generation) {
    _previewWarm?.cancel();
    if (_vttThumbnails.isNotEmpty || _storyboard != null) return;
    // Soon after playback settles: most scrubs come in the first minute.
    // On mobile data it waits longer, so the opening segments come first.
    _previewWarm = Timer(const Duration(seconds: 3), () async {
      if (!mounted || generation != _mediaGeneration) return;
      if (!_canGeneratePreview || _isLive) return;
      final url = _videoUrl;
      final ms = _controller?.value.duration.inMilliseconds ?? 0;
      if (url == null || ms < 60000) return;
      var metered = true;
      try {
        final c = await Connectivity().checkConnectivity();
        metered =
            !(c.contains(ConnectivityResult.wifi) ||
                c.contains(ConnectivityResult.ethernet));
      } catch (_) {}
      if (metered) await Future<void>.delayed(const Duration(seconds: 5));
      if (!mounted || generation != _mediaGeneration) return;
      FramePreviewService.warm(
        url: url,
        headers: _headers,
        durationMs: ms,
        hls: _isHls,
        metered: metered,
        cacheKey: _previewCacheKey,
        positionMs: _controller?.value.position.inMilliseconds ?? 0,
      );
      _plog('preview grid warming (${metered ? 'mobile data' : 'wifi'})');
    });
  }

  /// The episode, not the stream: stream addresses are signed and change,
  /// the frames of an episode do not. Null for a local file with no title
  /// behind it.
  String? get _previewCacheKey {
    final content = widget.args.contentUrl;
    if (content == null || content.isEmpty) return null;
    final ep =
        _window.current?.episode ?? widget.args.offlineEpisodeNumber ?? 0;
    return '${widget.args.provider}|$content|$ep|$_currentLang';
  }

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
      final idx = (ratio * totalCells).clamp(0, totalCells - 1).floor();
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
