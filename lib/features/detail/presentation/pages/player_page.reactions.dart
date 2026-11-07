// ignore_for_file: invalid_use_of_protected_member
part of 'player_page.dart';

/// Per-episode comments and timed reactions in the player.
///
/// Reactions are fetched once per episode, after the duration is known (the
/// heatmap needs it), and replayed from the position listener the skip offers
/// already use. Everything here is optional: a failed fetch leaves the
/// episode without reactions and playback does not notice.
class _EpisodeSocial {
  final ReactionScheduler scheduler = ReactionScheduler();
  final ValueNotifier<List<ReactionPop>> pops = ValueNotifier(const []);
  final ValueNotifier<List<double>> heatmap = ValueNotifier(const []);
  final bool overlayOn = const SocialPlaybackPrefs().reactionsOverlay;

  /// Bumped per episode, so a late answer for the previous one is dropped.
  int generation = 0;
  int durationSec = 0;
  DateTime? lastPost;

  void dispose() {
    pops.dispose();
    heatmap.dispose();
  }
}

extension _PlayerEpisodeSocial on _PlayerPageState {
  String? get _socialContentUrl {
    final url = widget.args.contentUrl;
    if (url == null || url.isEmpty || _isLive) return null;
    return url;
  }

  EpisodeEntity? get _socialEpisode =>
      widget.args.isSerial &&
          _episodeIndex >= 0 &&
          _episodeIndex < _episodes.length
      ? _episodes[_episodeIndex]
      : null;

  String? get _socialEpisodeKey => EpisodeKey.of(
    isSerial: widget.args.isSerial,
    episodeNumber: _socialEpisode?.episode,
    episodeIndex: _episodeIndex,
  );

  int? _socialPlayheadSec() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return null;
    return c.value.position.inSeconds;
  }

  void _resetEpisodeSocial() {
    _social.generation++;
    _social.scheduler.clear();
    _social.durationSec = 0;
    _social.pops.value = const [];
    _social.heatmap.value = const [];
  }

  Future<void> _loadEpisodeSocial() async {
    if (!_social.overlayOn) return;
    final url = _socialContentUrl;
    if (url == null) return;
    final generation = _social.generation;
    try {
      final timeline = await getIt<TimedReactionsDataSource>().fetch(
        provider: widget.args.provider,
        contentUrl: url,
        episodeKey: EpisodeKey.forReactions(_socialEpisodeKey),
      );
      if (!mounted || generation != _social.generation) return;
      _applyReactionTimeline(timeline);
    } catch (e) {
      _plog('reactions unavailable: $e');
    }
  }

  void _applyReactionTimeline(ReactionTimeline timeline) {
    if (_social.durationSec <= 0) {
      final c = _controller;
      if (c != null && c.value.isInitialized) {
        _social.durationSec = c.value.duration.inSeconds;
      }
    }
    _social.scheduler.load(timeline);
    _social.heatmap.value = timeline.isEmpty
        ? const []
        : timeline.heatmap(_social.durationSec);
  }

  void _tickEpisodeSocial(Duration position) {
    if (!_social.overlayOn || _social.scheduler.timeline.isEmpty) return;
    final next = _social.scheduler.at(position);
    final current = _social.pops.value;
    if (next.length == current.length) {
      var same = true;
      for (var i = 0; i < next.length && same; i++) {
        same = next[i] == current[i];
      }
      if (same) return;
    }
    _social.pops.value = next;
  }

  void _socialSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _openReactionPicker() async {
    final url = _socialContentUrl;
    if (url == null) return;
    if (!_hive.isLoggedIn) {
      _socialSnack('comments.please_sign_in'.tr());
      return;
    }
    _hideTimer?.cancel();
    final choice = await showReactionPicker(context);
    if (!mounted) return;
    _scheduleHide();
    if (choice == null) return;
    final last = _social.lastPost;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 5)) {
      _socialSnack('player.reaction_wait'.tr());
      return;
    }
    final atSec = _socialPlayheadSec() ?? 0;
    _social.lastPost = DateTime.now();
    final episodeKey = EpisodeKey.forReactions(_socialEpisodeKey);
    final generation = _social.generation;
    _applyReactionTimeline(
      _social.scheduler.timeline.withReaction(atSec, choice.kind, choice.value),
    );
    try {
      await getIt<TimedReactionsDataSource>().post(
        provider: widget.args.provider,
        contentUrl: url,
        episodeKey: episodeKey,
        atSec: atSec,
        kind: choice.kind,
        value: choice.value,
      );
    } on DioException catch (e) {
      if (generation != _social.generation) return;
      final data = e.response?.data;
      final message = data is Map ? data['message']?.toString() : null;
      _socialSnack(
        e.response?.statusCode == 429
            ? 'player.reaction_limit'.tr()
            : (message ?? 'player.reaction_failed'.tr()),
      );
    } catch (_) {
      _socialSnack('player.reaction_failed'.tr());
    }
  }

  Future<void> _openEpisodeComments() async {
    final url = _socialContentUrl;
    if (url == null) return;
    final ep = _socialEpisode;
    _hideTimer?.cancel();
    await showEpisodeComments(
      context,
      provider: widget.args.provider,
      contentUrl: url,
      episodeKey: _socialEpisodeKey,
      title: ep == null
          ? widget.args.title
          : 'player.episode_comments'.tr(args: [ep.numberLabel]),
      playheadSec: _socialPlayheadSec,
    );
    if (mounted) _scheduleHide();
  }

  /// Other viewers' reactions, at the start edge between the top bar and the
  /// subtitles.
  Widget _buildReactionLane() {
    if (!_social.overlayOn || _compact) return const SizedBox.shrink();
    return PositionedDirectional(
      start: 16,
      top: 0,
      bottom: 0,
      child: Align(
        alignment: const AlignmentDirectional(-1, -0.15),
        child: ReactionLane(pops: _social.pops),
      ),
    );
  }

  /// React and Comments, on the end edge while the controls are up.
  Widget _buildEpisodeSocialRail() {
    if (_compact || !_controlsVisible || _socialContentUrl == null) {
      return const SizedBox.shrink();
    }
    return PositionedDirectional(
      end: 8,
      top: 0,
      bottom: 0,
      child: Center(
        child: FadeTransition(
          opacity: _controlsAnimation,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _IconButton(
                icon: Icons.add_reaction_outlined,
                tooltip: 'player.react'.tr(),
                onTap: _openReactionPicker,
              ),
              const SizedBox(height: 8),
              _IconButton(
                icon: Icons.forum_outlined,
                tooltip: 'player.comments'.tr(),
                onTap: _openEpisodeComments,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The strip over the seek bar; [inset] is the track's own inset.
  Widget _buildReactionHeatmap(double inset) {
    if (!_social.overlayOn || _isLive) return const SizedBox.shrink();
    return Positioned(
      left: inset,
      right: inset,
      top: 2,
      height: 4,
      child: ValueListenableBuilder<List<double>>(
        valueListenable: _social.heatmap,
        builder: (_, bins, _) => ReactionHeatmap(bins: bins),
      ),
    );
  }
}
