// ignore_for_file: invalid_use_of_protected_member
part of 'player_page.dart';

/// The next episode, prepared and announced before this one ends.
extension _PlayerUpNext on _PlayerPageState {
  AutomationSettings? get _automation =>
      getIt.isRegistered<AutomationSettings>()
      ? getIt<AutomationSettings>()
      : null;

  /// The same conditions the end-of-episode auto-advance checks.
  bool get _willAutoAdvance =>
      !(_inParty && !_isPartyHost) &&
      !_sleepAtEpisodeEnd &&
      !_upNextDismissed &&
      _hive.autoPlayNextEpisode &&
      widget.args.isSerial &&
      _hasNextEpisode;

  String _prefetchKey(EpisodeEntity ep, String? lang) =>
      '${widget.args.provider}|${ep.mediaRef}|${lang ?? ''}';

  /// Resolves the next episode once this one is mostly watched, so moving on
  /// skips the resolve. Only the resolve: opening a second decoder would cost
  /// memory and heat for an episode that may never be played.
  void _maybePrefetchNext(Duration position, Duration duration) {
    if (!(_automation?.prefetchNextEpisode ?? false)) return;
    if (!widget.args.isSerial || _sleepAtEpisodeEnd) return;
    if (_inParty && !_isPartyHost) return;
    if (widget.args.offlineEpisodeNumber != null) return;
    if (!NextUp.shouldPrefetch(position, duration)) return;
    final index = _episodeIndex + 1;
    if (!_window.contains(index)) return;
    final ep = _episodes[index];
    if (ep.mediaRef.isEmpty) return;
    final lang = _resolveLangForEpisode(ep);
    final key = _prefetchKey(ep, lang);
    if (_nextResolve.covers(key)) return;
    _plog('prefetching next episode ref=${ep.mediaRef}');
    unawaited(
      _nextResolve.fill(key, () async {
        final result = await _resolve(
          ref: ep.mediaRef,
          provider: widget.args.provider,
          lang: lang,
        );
        return result is Success<MediaResolveEntity> ? result.value : null;
      }),
    );
  }

  Future<MediaResolveEntity?> _takePrefetched(EpisodeEntity ep, String? lang) =>
      _nextResolve.take(_prefetchKey(ep, lang));

  void _playNextNow() {
    if (!_hasNextEpisode) return;
    _saveHistoryForNextEpisode();
    _autoAdvanced = true;
    _loadEpisode(_episodeIndex + 1);
  }

  void _dismissUpNext() {
    if (mounted) setState(() => _upNextDismissed = true);
  }

  Widget _buildUpNextPrompt() {
    final controller = _controller;
    final countdown = _automation?.upNextSeconds ?? 0;
    if (controller == null ||
        countdown <= 0 ||
        _initializing ||
        _isPip ||
        isTvPlatform ||
        !_willAutoAdvance ||
        !_window.contains(_episodeIndex + 1)) {
      return const SizedBox.shrink();
    }
    final next = _episodes[_episodeIndex + 1];
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        if (!value.isInitialized) return const SizedBox.shrink();
        final left = NextUp.promptSecondsLeft(
          position: value.position,
          duration: value.duration,
          countdownSeconds: countdown,
        );
        if (left == null) return const SizedBox.shrink();
        final base = _controlsVisible ? 92.0 : 28.0;
        return Positioned(
          right: 20,
          bottom: _activeSkip != null ? base + 52 : base,
          child: _UpNextCard(
            label: next.label.trim().isNotEmpty
                ? next.label
                : 'automation.episode_n'.tr(args: ['${next.episode}']),
            secondsLeft: left,
            countdown: countdown,
            onPlayNow: _playNextNow,
            onCancel: _dismissUpNext,
          ),
        );
      },
    );
  }

  /// Watched automatic downloads are cleaned up once the history row that
  /// says so has been written.
  void _schedulePruneAfterPlayback() {
    if (getIt.isRegistered<AutoDownloadService>()) {
      getIt<AutoDownloadService>().pruneSoon();
    }
  }
}

class _UpNextCard extends StatelessWidget {
  const _UpNextCard({
    required this.label,
    required this.secondsLeft,
    required this.countdown,
    required this.onPlayNow,
    required this.onCancel,
  });

  final String label;
  final int secondsLeft;
  final int countdown;
  final VoidCallback onPlayNow;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.78),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 264,
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 30,
                  height: 30,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: countdown <= 0 ? 0 : 1 - secondsLeft / countdown,
                        strokeWidth: 2.4,
                        color: AppColors.primary,
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                      ),
                      Text(
                        '$secondsLeft',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'automation.up_next'.tr(),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text('general.cancel'.tr()),
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  onPressed: onPlayNow,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.skip_next_rounded, size: 18),
                  label: Text('automation.play_now'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
