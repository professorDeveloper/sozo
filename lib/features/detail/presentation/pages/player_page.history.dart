part of 'player_page.dart';

extension _PlayerHistory on _PlayerPageState {
  void _scheduleHistorySave() {
    _historyTimer?.cancel();
    _historyTimer = Timer(const Duration(seconds: 5), () {
      _saveHistory();
      // Deliberately not inside _saveHistory: that returns early for a
      // finished episode, a title with no url and a session under ten seconds,
      // and none of those are reasons to leave a stale line on somebody's
      // Discord profile.
      _publishDiscordPresence();
    });
  }

  /// Tells Discord what is playing, if the viewer asked for that.
  ///
  /// Called on the same five-second tick as the history save. The service
  /// coalesces internally — Discord drops presence updates sent more often
  /// than roughly one every fifteen seconds — so calling it often is free and
  /// calling it rarely would mean the episode line lagged behind the episode.
  void _publishDiscordPresence() {
    if (!_hive.discordPresenceEnabled) return;

    final discord = getIt<DiscordPresenceService>();
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;

    final now = DateTime.now();
    final position = c.value.position;
    final duration = c.value.duration;

    discord.update(
      DiscordActivity(
        title: widget.args.title,
        // The episode line only for a series; a film has none, and an empty
        // second row on a Discord card reads as a bug.
        subtitle: widget.args.isSerial ? _episodeLabelOnly() : null,
        imageUrl: widget.args.thumbnail,
        imageText: widget.args.provider,
        // Discord renders the elapsed bar from these, so `start` is now minus
        // the position rather than when the episode opened — which is what
        // makes seeking move the bar instead of leaving it wrong.
        startedAt: now.subtract(position),
        endsAt: duration > Duration.zero ? now.add(duration - position) : null,
        watchUrl: 'https://sozo.framer.website/',
      ),
    );
  }

  /// Just the episode part, without the series name repeated from the line
  /// above it.
  String? _episodeLabelOnly() {
    if (_episodeIndex < 0 || _episodeIndex >= _episodes.length) {
      return null;
    }
    final ep = _episodes[_episodeIndex];
    final label = ep.label.trim();
    return label.isEmpty ? 'Episode ${ep.episode}' : label;
  }

  void _saveHistory() {
    if (_playbackWatch.elapsed.inSeconds < 10) return;

    // Time watched since the last save, banked before anything can return
    // early. History skips a finished episode and a title with no url; the
    // seconds were still watched, and a statistics page that lost the last
    // stretch of everything somebody finished would be wrong in a way they
    // could feel.
    _bankWatchTime();

    final contentUrl = widget.args.contentUrl;
    if (contentUrl == null || contentUrl.isEmpty) return;
    final c = _controller;
    final posMs = c != null && c.value.isInitialized
        ? c.value.position.inMilliseconds
        : 0;
    final durMs = c != null && c.value.isInitialized
        ? c.value.duration.inMilliseconds
        : 0;

    if (durMs > 0 && posMs >= durMs - 2000) return;

    EpisodeEntity? ep;
    if (widget.args.isSerial &&
        _episodeIndex >= 0 &&
        _episodeIndex < _episodes.length) {
      ep = _episodes[_episodeIndex];
    }

    _history.save(
      HistoryItem(
        contentUrl: contentUrl,
        provider: widget.args.provider,
        title: widget.args.title,
        thumbnail: widget.args.thumbnail,
        isSerial: widget.args.isSerial,
        episodeIndex: widget.args.isSerial ? _episodeIndex : null,
        episodeNumber: ep?.episode,
        episodeLabel: ep?.label,
        positionMs: posMs,
        durationMs: durMs,
        watchedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Adds the stretch since the last tick to the running totals.
  ///
  /// Wall-clock rather than stream position, and deliberately: a seek is not
  /// watching, and position deltas would count a scrub to the end as an hour.
  /// Paused time is not counted either — the tick only fires while playing.
  ///
  /// Nothing is recorded in incognito. The app promises that mode saves
  /// nothing, and a total quietly including those hours would make the promise
  /// false where it matters most.
  void _bankWatchTime() {
    final elapsed = _progress.bank(_playbackWatch.elapsed);
    if (elapsed <= 0) return;
    if (_hive.isIncognito) return;
    unawaited(
      _watchStats.record(
        seconds: elapsed,
        provider: widget.args.provider,
      ),
    );
  }

  void _saveHistoryForNextEpisode() {
    final contentUrl = widget.args.contentUrl;
    if (contentUrl == null || contentUrl.isEmpty) return;
    if (!widget.args.isSerial) return;

    final nextIdx = _episodeIndex + 1;
    if (nextIdx >= _episodes.length) return;

    final nextEp = _episodes[nextIdx];
    _history.save(
      HistoryItem(
        contentUrl: contentUrl,
        provider: widget.args.provider,
        title: widget.args.title,
        thumbnail: widget.args.thumbnail,
        isSerial: true,
        episodeIndex: nextIdx,
        episodeNumber: nextEp.episode,
        episodeLabel: nextEp.label,
        positionMs: 0,
        durationMs: 0,
        watchedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Reports the episode in progress to every connected tracker once it is far
  /// enough through.
  ///
  /// Fires at [_kTrackerThreshold] rather than at the very end because a viewer
  /// who skips the ending, or who closes the player on the credits, has still
  /// watched the episode — waiting for the last frame loses those entirely.
  ///
  /// Everything about this is fire-and-forget: no await on the caller's path,
  /// no snackbar, no error state. It runs during playback, and a tracker being
  /// down is not the viewer's problem to see.
  ///
  /// The guard set is shared across trackers rather than kept per tracker. One
  /// episode is one event; a MAL write that fails must not be retried by the
  /// next tick, which is exactly what a per-tracker set would cause.
  void _maybeReportTrackers() {
    // Incognito covers the trackers too. Suppressing local history while still
    // pushing the episode to AniList and MAL would leave the record in the one
    // place the viewer cannot quietly clear — someone else's server.
    if (_hive.isIncognito) return;

    final contentUrl = widget.args.contentUrl;
    if (contentUrl == null || contentUrl.isEmpty) return;

    final anilist = getIt<AnilistTracker>();
    final mal = getIt<MalTracker>();
    if (!anilist.isConnected && !mal.isConnected) return;

    // The window says which episode; WatchProgress decides whether to report
    // it. The movie-is-episode-1 rule, the zero-or-less guard and the
    // once-per-episode ledger all live there now.
    final episodeNumber = _progress.episodeToReport(
      isSerial: widget.args.isSerial,
      episodeNumber: _window.current?.episode,
    );
    if (episodeNumber == null) return;

    for (final tracker in <Future<int?> Function()>[
      if (anilist.isConnected)
        () => anilist.reportEpisode(
              provider: widget.args.provider,
              contentUrl: contentUrl,
              title: widget.args.title,
              episodeNumber: episodeNumber,
            ),
      if (mal.isConnected)
        () => mal.reportEpisode(
              provider: widget.args.provider,
              contentUrl: contentUrl,
              title: widget.args.title,
              episodeNumber: episodeNumber,
            ),
    ]) {
      unawaited(tracker().catchError((Object _) => null));
    }
  }

  Future<void> _pingStreak() async {
    try {
      final result = await getIt<StreakService>().ping();
      if (result == null || !mounted) return;
      final milestone = result.newMilestone;
      if (milestone != null) {
        await StreakMilestoneDialog.show(
          context,
          milestone,
          freezeAwarded: result.freezeAwarded,
        );
      }
      // Independent of the milestone: a ping can both cross a milestone AND
      // consume a banked freeze to rescue a missed day. Surface the freeze
      // rescue too (re-checking mounted after the milestone dialog's await).
      if (result.freezeSaved && mounted) {
        await StreakFreezeSavedDialog.show(context);
      }
    } catch (_) {}
  }

  /// Asks which stream to keep, when there is more than one to keep.
  ///
  /// Returns the chosen url, or null if the sheet was dismissed. With a single
  /// offer there is no question to ask, so none is asked.
  Future<DownloadChoice?> _pickDownloadUrl() async {
    final offers = DownloadChoices.from(
      sources: _videoSources,
      currentIndex: _currentSourceIndex,
      currentUrl: _videoUrl,
      currentHeaders: _headers.isNotEmpty ? _headers : widget.args.headers,
      hasDirective: _extractorConfig != null,
    );
    if (offers.isEmpty) return null;
    if (offers.length == 1) return offers.single;

    return showAdaptiveModal<DownloadChoice>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
                child: Text(
                  'detail.download_choose_server'.tr(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text(
                  widget.args.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12.5,
                  ),
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              for (final offer in offers)
                _SettingsTile(
                  icon: Icons.download_rounded,
                  label: offer.label,
                  // The current stream is the one that is certain to work,
                  // because it is the only url already resolved.
                  value: offer.isCurrent
                      ? 'detail.download_playing_now'.tr()
                      : offer.needsSniff && offer.detail.isEmpty
                          ? 'detail.download_will_resolve'.tr()
                          : offer.detail,
                  onTap: () => Navigator.of(sheetContext).pop(offer),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Turns a picked offer into a downloadable url.
  ///
  /// A mirror behind an extractor directive is an embed page, so it goes
  /// through the same WebView extraction playback uses. That takes seconds and
  /// can fail, so it happens behind a barrier the viewer can see, and a failure
  /// says what to do instead rather than starting a download that would save
  /// HTML.
  Future<DownloadChoice?> _resolveChoice(DownloadChoice choice) async {
    final cfg = _extractorConfig;
    if (!choice.needsSniff || cfg == null) return choice;

    // canPop: false, because Android back would otherwise dismiss the barrier
    // and leave this method holding a pop() that lands on the PLAYER route —
    // ending playback up to 25 seconds later, mid-episode, for no visible
    // reason. Back during a resolve now does nothing; the sniff has its own
    // watchdog.
    var barrierOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      ),
    ).whenComplete(() => barrierOpen = false);
    ExtractedStream? sniffed;
    try {
      sniffed = await getIt<WebViewStreamExtractor>().extract(
        pageUrl: choice.url,
        config: cfg,
        pageHeaders: choice.headers,
      );
    } catch (_) {
      sniffed = null;
    }
    // Only ever pops the barrier: if it is already gone, popping again would
    // take the player route with it.
    if (mounted && barrierOpen) {
      barrierOpen = false;
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (!mounted) return null;

    if (sniffed == null || sniffed.url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('detail.download_needs_playback'.tr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return null;
    }
    return DownloadChoice(
      url: sniffed.url,
      // Sniffed headers win for the same reason they do in playback: they are
      // the ones the page actually sent, and the CDN gates on exactly those.
      headers: {...choice.headers, ...sniffed.headers},
      label: choice.label,
      detail: choice.detail,
      isCurrent: false,
      sizeBytes: choice.sizeBytes,
    );
  }

  Future<void> _startDownload() async {
    // Downloading took whatever was on screen, so somebody watching 480p to
    // save data could not keep the 1080p without switching playback to it
    // first. The sheet only appears when there is a genuine choice.
    final picked = await _pickDownloadUrl();
    if (!mounted) return;
    if (picked == null || picked.url.isEmpty) return;
    final choice = await _resolveChoice(picked);
    if (!mounted || choice == null || choice.url.isEmpty) return;
    final url = choice.url;

    EpisodeEntity? ep;
    if (widget.args.isSerial &&
        _episodeIndex >= 0 &&
        _episodeIndex < _episodes.length) {
      ep = _episodes[_episodeIndex];
    }

    // One request, built by the domain, so the player, the episode list and
    // the detail page cannot invent different ids for the same episode — which
    // is how the list once showed no progress for a download the player had
    // started, and starting it from the other screen fetched the same file
    // twice.
    final outcome = await getIt<EnqueueDownloadUseCase>()(
      DownloadRequest.video(
        contentUrl: widget.args.contentUrl ?? url,
        provider: widget.args.provider,
        title: widget.args.title,
        sourceUrl: url,
        thumbnailUrl: widget.args.thumbnail,
        // The picked mirror's own headers. Sending the playing stream's here
        // would 403 on every host but the one already on screen.
        headers: choice.headers,
        isSerial: widget.args.isSerial,
        episodeNumber: widget.args.isSerial && ep != null ? ep.episode : null,
        episodeLabel: ep?.label,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(downloadOutcomeMessage(outcome)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

}
