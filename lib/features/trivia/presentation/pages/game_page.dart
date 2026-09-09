import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/player/media_controller.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/features/trivia/domain/entities/trivia_option_entity.dart';
import 'package:soplay/features/trivia/presentation/bloc/game/game_bloc.dart';
import 'package:soplay/features/trivia/presentation/bloc/game/game_event.dart';
import 'package:soplay/features/trivia/presentation/bloc/game/game_state.dart';
import 'package:soplay/features/trivia/presentation/trivia_args.dart';
import 'package:soplay/features/trivia/presentation/widgets/buff_empty_panel.dart';
import 'package:soplay/features/trivia/presentation/widgets/countdown_ring.dart';
import 'package:soplay/features/trivia/presentation/widgets/option_chip.dart';
import 'package:soplay/features/trivia/presentation/widgets/progress_dots.dart';

/// Full-screen trivia gameplay. Owns a [GameBloc] (which owns the round + the
/// countdown, whose window comes from the round payload) and a reused
/// shorts-style [PlayerController] so each clip plays as smoothly as the shorts
/// feed. Timer + player are always disposed on pop, and back is guarded behind
/// a forfeit confirm — no leaked timers / ANR.
class GamePage extends StatefulWidget {
  const GamePage({super.key, required this.args});

  final GameArgs args;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  @override
  Widget build(BuildContext context) {
    final a = widget.args;
    return BlocProvider(
      create: (_) => getIt<GameBloc>()
        ..add(RoundStarted(
          mode: a.mode,
          actorId: a.actorRef?.id,
          kind: a.actorRef?.kind,
          round: a.presetRound,
        )),
      child: const _GameView(),
    );
  }
}

class _GameView extends StatefulWidget {
  const _GameView();

  @override
  State<_GameView> createState() => _GameViewState();
}

class _GameViewState extends State<_GameView> {
  PlayerController? _vpc;
  int _playerToken = 0;
  bool _hasError = false;
  String? _loadedClipId;

  Timer? _advanceTimer;
  bool _navigated = false;

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _playerToken++;
    _vpc?.dispose();
    super.dispose();
  }

  // ── player ───────────────────────────────────────────────────────────────
  Future<void> _initPlayer(String url) async {
    final token = ++_playerToken;
    final previous = _vpc;
    _vpc = null;
    _hasError = false;
    if (mounted) setState(() {});
    await previous?.dispose();

    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      if (mounted) setState(() => _hasError = true);
      return;
    }

    try {
      final c = PlayerController.networkUrl(Uri.parse(trimmed));
      await c.initialize();
      if (!mounted || token != _playerToken) {
        await c.dispose();
        return;
      }
      c.setLooping(true);
      c.setVolume(1);
      c.play();
      setState(() => _vpc = c);
    } catch (_) {
      if (mounted && token == _playerToken) {
        setState(() => _hasError = true);
      }
    }
  }

  // ── advance / navigation ───────────────────────────────────────────────────
  void _scheduleAdvance(GameBloc bloc, bool isLast) {
    _advanceTimer?.cancel();
    _advanceTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      bloc.add(isLast ? const RoundCompleted() : const NextClip());
    });
  }

  void _onState(BuildContext context, GameState state) {
    final clip = state.currentClip;
    if (clip != null && clip.clipId != _loadedClipId) {
      _loadedClipId = clip.clipId;
      _initPlayer(clip.videoUrl);
    }
    if (state.phase == GamePhase.revealed) {
      _vpc?.pause();
      _scheduleAdvance(context.read<GameBloc>(), state.isLastClip);
    }
    if (state.phase == GamePhase.finished &&
        state.result != null &&
        !_navigated) {
      _navigated = true;
      _advanceTimer?.cancel();
      // The actor rides along so the result screen can enrich the share card
      // and point "play again" back at the same actor — without it every
      // rematch started an actor-less round.
      context.pushReplacement(
        '/trivia/result',
        extra: ResultArgs(result: state.result!, actor: state.actor),
      );
    }
  }

  Future<void> _handleExit(BuildContext context, GameState state) async {
    if (state.phase == GamePhase.finished || state.phase == GamePhase.error) {
      context.pop();
      return;
    }
    final leave = await _confirmForfeit(context);
    if (leave && context.mounted) context.pop();
  }

  Future<bool> _confirmForfeit(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.border.withValues(alpha: 0.6)),
        ),
        title: Text(
          'trivia.forfeit_title'.tr(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'trivia.forfeit_body'.tr(),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('trivia.keep_playing'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'trivia.forfeit_confirm'.tr(),
              style: TextStyle(color: AppColors.primaryLight),
            ),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _watchFull(BuildContext context, GameState state) {
    final url = state.reveal?.contentUrl;
    if (url == null || url.isEmpty) return;
    context.push('/detail', extra: DetailArgs(contentUrl: url));
  }

  // ── build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return BlocConsumer<GameBloc, GameState>(
      listenWhen: (prev, curr) =>
          prev.phase != curr.phase ||
          prev.currentClip?.clipId != curr.currentClip?.clipId,
      listener: _onState,
      builder: (context, state) {
        return PopScope(
          canPop:
              state.phase == GamePhase.finished || state.phase == GamePhase.error,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final leave = await _confirmForfeit(context);
            if (leave && context.mounted) context.pop();
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: _buildBody(context, state),
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, GameState state) {
    switch (state.phase) {
      case GamePhase.loading:
        return const _LoadingView();
      case GamePhase.error:
        return _ErrorView(
          reason: state.reason,
          message: state.message,
          onBack: () => context.pop(),
        );
      case GamePhase.playing:
      case GamePhase.revealed:
      case GamePhase.finished:
        return Stack(
          fit: StackFit.expand,
          children: [
            _buildVideo(),
            const _BottomScrim(),
            SafeArea(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 12, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _IconButton(
                      icon: CupertinoIcons.xmark,
                      onTap: () => _handleExit(context, state),
                    ),
                    Expanded(
                      child: ProgressDots(
                        total: state.totalClips,
                        currentIndex: state.index,
                      ),
                    ),
                    // The window is whatever the round payload declares
                    // (server-owned — 10s today, 15s on the legacy fallback).
                    // `ceil` mirrors GameBloc._secondsFor so the arc starts at
                    // exactly 1.0 on the first tick.
                    CountdownRing(
                      secondsRemaining: state.timeRemaining,
                      totalSeconds: (state.deadlineMs / 1000).ceil(),
                    ),
                  ],
                ),
              ),
            ),
            _buildBottom(context, state),
          ],
        );
    }
  }

  Widget _buildVideo() {
    if (_hasError) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Icon(Icons.broken_image_outlined,
              color: Colors.white24, size: 48),
        ),
      );
    }
    final c = _vpc;
    if (c == null) {
      return const ColoredBox(color: Colors.black, child: _Spinner());
    }
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: c,
      builder: (_, value, _) {
        if (!value.isInitialized) {
          return const ColoredBox(color: Colors.black, child: _Spinner());
        }
        final ratio = value.aspectRatio <= 0 ? 9 / 16 : value.aspectRatio;
        return ColoredBox(
          color: Colors.black,
          child: Center(
            child: AspectRatio(aspectRatio: ratio, child: c.buildView()),
          ),
        );
      },
    );
  }

  Widget _buildBottom(BuildContext context, GameState state) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final clip = state.currentClip;
    if (clip == null) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RevealPanel(
              state: state,
              onWatchFull: () => _watchFull(context, state),
            ),
            const SizedBox(height: 14),
            _OptionsGrid(
              options: clip.options,
              state: state,
              onSelect: (id) =>
                  context.read<GameBloc>().add(OptionSelected(id)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── options ────────────────────────────────────────────────────────────────
class _OptionsGrid extends StatelessWidget {
  const _OptionsGrid({
    required this.options,
    required this.state,
    required this.onSelect,
  });

  final List<TriviaOptionEntity> options;
  final GameState state;
  final ValueChanged<String> onSelect;

  bool get _locked =>
      state.phase != GamePhase.playing || state.selectedOptionId != null;

  OptionChipStatus _statusFor(TriviaOptionEntity opt) {
    final reveal = state.reveal;
    if (state.phase == GamePhase.revealed && reveal != null) {
      if (opt.title == reveal.correctTitle) return OptionChipStatus.correct;
      if (opt.optionId == state.selectedOptionId) return OptionChipStatus.wrong;
      return OptionChipStatus.dimmed;
    }
    if (opt.optionId == state.selectedOptionId) {
      return OptionChipStatus.selected;
    }
    return OptionChipStatus.idle;
  }

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var row = 0; row < options.length; row += 2)
          Padding(
            padding: EdgeInsets.only(top: row == 0 ? 0 : 10),
            child: Row(
              children: [
                Expanded(child: _cell(options[row])),
                if (row + 1 < options.length) ...[
                  const SizedBox(width: 10),
                  Expanded(child: _cell(options[row + 1])),
                ] else
                  const Expanded(child: SizedBox.shrink()),
              ],
            ),
          ),
      ],
    );
  }

  Widget _cell(TriviaOptionEntity opt) {
    return OptionChip(
      label: opt.title,
      status: _statusFor(opt),
      onTap: _locked ? null : () => onSelect(opt.optionId),
    );
  }
}

// ── reveal ───────────────────────────────────────────────────────────────────
class _RevealPanel extends StatelessWidget {
  const _RevealPanel({required this.state, required this.onWatchFull});

  final GameState state;
  final VoidCallback onWatchFull;

  @override
  Widget build(BuildContext context) {
    final reveal = state.reveal;
    final show = state.phase == GamePhase.revealed && reveal != null;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.35),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: !show
          ? const SizedBox(width: double.infinity, key: ValueKey('empty'))
          : Container(
              key: const ValueKey('reveal'),
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                // Surface card scale: radius 12. The border keeps its semantic
                // colour (green/red) because it is the correctness signal.
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (reveal.correct
                          ? AppColors.success
                          : AppColors.error)
                      .withValues(alpha: 0.5),
                  width: 1.2,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _Poster(url: reveal.poster),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              (reveal.correct
                                      ? 'trivia.correct'
                                      : 'trivia.the_answer')
                                  .tr(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: reveal.correct
                                    ? AppColors.success
                                    : AppColors.errorLight,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              reveal.correctTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _PointsBadge(
                        points: reveal.points,
                        correct: reveal.correct,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: onWatchFull,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(kButtonRadius),
                        ),
                      ),
                      icon: const Icon(CupertinoIcons.play_fill, size: 16),
                      label: Text(
                        'trivia.watch_full'.tr(),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    // 54 × 78 → 0.692, inside the app's emergent 0.68–0.70 poster band, at the
    // artwork-card radius of 10.
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 54,
        height: 78,
        child: url.isEmpty
            ? const HomeImagePlaceholder(icon: Icons.movie_outlined)
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const HomeImagePlaceholder(icon: Icons.movie_outlined),
                loadingBuilder: (_, child, chunk) => chunk == null
                    ? child
                    : const HomeImagePlaceholder(icon: Icons.movie_outlined),
              ),
      ),
    );
  }
}

class _PointsBadge extends StatelessWidget {
  const _PointsBadge({required this.points, required this.correct});

  final int points;
  final bool correct;

  @override
  Widget build(BuildContext context) {
    final color = correct ? AppColors.success : AppColors.textHint;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.elasticOut,
      builder: (_, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(
          '+$points',
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

// ── chrome ───────────────────────────────────────────────────────────────────
class _BottomScrim extends StatelessWidget {
  const _BottomScrim();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Color(0x00000000),
              Color(0xCC000000),
            ],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 34,
        height: 34,
        child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2.5),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Spinner(),
          const SizedBox(height: 16),
          Text(
            'trivia.building_round'.tr(),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

/// The round could not be built or finalized. A 409 (and a round that came back
/// with no clips) is a content state, not a fault, so it gets its own localized
/// copy instead of echoing the server's English sentence into an Uzbek UI.
/// The button pops back to whoever pushed the game — normally the actor page.
class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.reason,
    required this.message,
    required this.onBack,
  });

  final GameErrorReason reason;
  final String? message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final notReady = reason == GameErrorReason.notEnoughClips;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: BuffEmptyPanel(
            icon: notReady
                ? CupertinoIcons.film
                : CupertinoIcons.exclamationmark_triangle,
            title: notReady
                ? 'trivia.actor_not_ready'.tr()
                : 'trivia.round_failed'.tr(),
            body: notReady
                ? 'trivia.actor_not_ready_body'.tr()
                : (message?.isNotEmpty == true ? message : null),
            actionLabel: 'trivia.go_back'.tr(),
            onAction: onBack,
          ),
        ),
      ),
    );
  }
}
