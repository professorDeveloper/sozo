// ignore_for_file: invalid_use_of_protected_member
part of 'player_page.dart';

/// Opening and ending skipping, backed by AniSkip.
///
/// Gated on the provider's own category rather than on whether a match came
/// back. AniSkip is keyed on MyAnimeList, and the id lookup falls back to a
/// title search — hand that an Uzbek film and it will occasionally find *some*
/// anime with a similar name and start offering to skip ninety seconds of it.
/// Asking the provider whether this is an anime source at all is one cheap
/// check that removes the entire class of false match.
///
/// The button is the default and auto-skip is opt-in. These times are
/// crowd-sourced: a wrong one that jumps the viewer into the middle of the
/// episode is a much worse first impression than a button they chose not to
/// press. Once someone trusts it, the setting is there.
extension _PlayerAniSkip on _PlayerPageState {
  bool get _aniSkipEligible =>
      _hive.providerCategory(widget.args.provider) == 'anime';

  /// Look up skip times for whatever is playing now.
  ///
  /// Called once the duration is known, because AniSkip uses episode length to
  /// reject submissions timed against a different cut.
  Future<void> _loadSkipTimes() async {
    if (!_aniSkipEligible || _isLive) return;
    final contentUrl = widget.args.contentUrl;
    if (contentUrl == null || contentUrl.isEmpty) return;

    final int episodeNumber;
    if (widget.args.isSerial) {
      if (_episodeIndex < 0 || _episodeIndex >= _episodes.length) {
        return;
      }
      episodeNumber = _episodes[_episodeIndex].episode;
    } else {
      // A film is episode 1 as far as AniSkip is concerned, the same way it is
      // for the trackers.
      episodeNumber = 1;
    }
    if (episodeNumber <= 0) return;

    final c = _controller;
    final length = c != null && c.value.isInitialized
        ? c.value.duration
        : Duration.zero;

    final intervals = await getIt<AniSkipService>().intervalsFor(
      provider: widget.args.provider,
      contentUrl: contentUrl,
      title: widget.args.title,
      episodeNumber: episodeNumber,
      episodeLength: length,
    );
    if (!mounted) return;
    setState(() {
      // load() drops the unusable ones, so nothing downstream has to remember
      // that a two-second interval is a bad submission rather than an opening.
      _skips.load(intervals);
      _activeSkip = null;
    });
  }

  /// Clear per-episode state. Called when the episode changes.
  void _resetSkipTimes() {
    _skips.clear();
    _activeSkip = null;
  }

  /// Decide whether a Skip offer belongs on screen at [position].
  ///
  /// Driven from the existing position listener rather than its own ticker:
  /// that listener already fires on every frame update the player receives, and
  /// a second timer would only be a second thing to keep in sync.
  void _updateActiveSkip(Duration position) {
    if (_skips.intervals.isEmpty) return;

    // Inside the interval, not already taken, not watched past — all three in
    // one place now, with fourteen tests over them.
    final active = _skips.offerAt(position);

    if (identical(active, _activeSkip)) return;
    if (active == null && _activeSkip == null) return;

    if (active != null && _hive.autoSkipIntro) {
      _takeSkip(active);
      return;
    }
    setState(() => _activeSkip = active);
  }

  /// Seek past [interval].
  ///
  /// Recorded in [_skipsTaken] so seeking back into the opening — to rewatch
  /// it, or because the viewer overshot — does not re-arm the same offer and,
  /// with auto-skip on, does not fight the viewer for control of the position.
  Future<void> _takeSkip(SkipInterval interval) async {
    _skips.take(interval);
    if (mounted) setState(() => _activeSkip = null);
    try {
      await _controller?.seekTo(_skips.targetFor(interval));
    } catch (_) {
      // A failed seek leaves playback where it was, which is survivable; the
      // offer stays retired so it does not loop.
    }
  }

  /// The floating "Skip opening / Skip ending" button, or nothing.
  Widget _buildSkipButton() {
    final active = _activeSkip;
    if (active == null || !_controlsCanShowSkip) {
      return const SizedBox.shrink();
    }
    final label = active.type == 'ed'
        ? 'player.skip_ending'.tr()
        : 'player.skip_opening'.tr();
    return Positioned(
      right: 20,
      bottom: _controlsVisible ? 92 : 28,
      child: AnimatedOpacity(
        opacity: 1,
        duration: const Duration(milliseconds: 150),
        child: Material(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _takeSkip(active),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.fast_forward_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Suppressed in the places a floating button would be wrong: picture-in-
  /// picture has no room for it, and a party guest skipping would desync the
  /// room rather than the episode.
  bool get _controlsCanShowSkip => !_isPip && !(_inParty && !_isPartyHost);
}

/// Switching to a source that still works.
///
/// Lives beside the player rather than inside [AlternateSourceService] because
/// only the player knows what is currently on screen: which episode number the
/// viewer had reached, and that leaving means replacing this route rather than
/// stacking another player on top of it.
extension _PlayerAlternateSources on _PlayerPageState {
  /// The episode number to look for on the other source, or null for a film.
  int? get _currentEpisodeNumber {
    if (!widget.args.isSerial) return null;
    if (_episodeIndex < 0 || _episodeIndex >= _episodes.length) {
      return null;
    }
    final n = _episodes[_episodeIndex].episode;
    return n > 0 ? n : null;
  }

  /// Offers the same title on another provider.
  ///
  /// Reached two ways, and the difference is [keepPosition]. From the error
  /// view there is nothing to resume to. From the settings sheet the viewer is
  /// part-way through and switching *because* this source is struggling — so
  /// the position travels with them and the episode picks up where it was,
  /// which is what makes switching worth doing instead of going back.
  Future<void> _openAlternateSources({bool keepPosition = false}) async {
    final controller = _controller;
    final resumeAt = keepPosition &&
            controller != null &&
            controller.value.isInitialized
        ? controller.value.position
        : Duration.zero;

    final args = await AlternateSourceSheet.show(
      context,
      title: widget.args.title,
      provider: widget.args.provider,
      category: _hive.providerCategory(widget.args.provider),
      episodeNumber: _currentEpisodeNumber,
      headers: widget.args.headers,
      resumeAt: resumeAt,
    );
    if (args == null || !mounted) return;
    // pushReplacement, not push. Either the player being left is showing an
    // error and has nothing to come back to, or it is the source the viewer
    // just chose to abandon — stacking a second one would leave the discarded
    // screen behind the working one for the back button to land on.
    context.pushReplacement('/player', extra: args);
  }
}
