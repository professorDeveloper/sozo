import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/trivia/domain/entities/challenge_entity.dart';
import 'package:soplay/features/trivia/presentation/bloc/challenge/challenge_bloc.dart';
import 'package:soplay/features/trivia/presentation/bloc/challenge/challenge_event.dart';
import 'package:soplay/features/trivia/presentation/bloc/challenge/challenge_state.dart';
import 'package:soplay/features/trivia/presentation/trivia_args.dart';

/// Deep-link target for `soplay://trivia/challenge/<code>`: shows the challenger
/// and the score to beat, then materializes a round from the frozen 10 clips and
/// hands it to the game.
class ChallengeLandingPage extends StatelessWidget {
  const ChallengeLandingPage({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ChallengeBloc>(
      create: (_) => getIt<ChallengeBloc>()..add(ChallengeOpened(code)),
      child: _ChallengeLandingView(code: code),
    );
  }
}

class _ChallengeLandingView extends StatelessWidget {
  const _ChallengeLandingView({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: BlocConsumer<ChallengeBloc, ChallengeState>(
        listenWhen: (a, b) =>
            b.status == ChallengeStatus.joined && b.round != null,
        listener: (context, state) {
          openGame(
            context,
            GameArgs(challengeCode: code, presetRound: state.round),
          );
        },
        builder: (context, state) {
          switch (state.status) {
            case ChallengeStatus.initial:
            case ChallengeStatus.loading:
              return const _LoadingView();
            case ChallengeStatus.error:
              return _ErrorView(
                message: state.message,
                onRetry: () =>
                    context.read<ChallengeBloc>().add(ChallengeOpened(code)),
              );
            case ChallengeStatus.loaded:
            case ChallengeStatus.joining:
            case ChallengeStatus.joined:
              final challenge = state.challenge;
              if (challenge == null) return const _LoadingView();
              return _ChallengeCard(
                challenge: challenge,
                joining: state.status == ChallengeStatus.joining ||
                    state.status == ChallengeStatus.joined,
                onPlay: () {
                  HapticFeedback.mediumImpact();
                  context.read<ChallengeBloc>().add(ChallengeJoined(code));
                },
              );
          }
        },
      ),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({
    required this.challenge,
    required this.joining,
    required this.onPlay,
  });

  final ChallengeEntity challenge;
  final bool joining;
  final VoidCallback onPlay;

  int get _scoreToBeat {
    var best = 0;
    for (final p in challenge.participants) {
      if (p.score > best) best = p.score;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final topSafe = MediaQuery.paddingOf(context).top;
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    final actorUrl = challenge.actor?.profileUrl ?? '';

    return Stack(
      children: [
        if (actorUrl.isNotEmpty) _Backdrop(url: actorUrl),
        Positioned(
          top: topSafe + 8,
          left: 8,
          child: GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  width: 38,
                  height: 38,
                  color: Colors.black.withValues(alpha: 0.38),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const _SwordsBadge(),
                const SizedBox(height: 20),
                Text(
                  'trivia.challenge_from'.tr(
                    namedArgs: {'name': challenge.creatorUsername},
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                if (challenge.actor != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    challenge.actor!.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
                const SizedBox(height: 26),
                _ScoreToBeat(score: _scoreToBeat),
                const SizedBox(height: 14),
                Text(
                  // Not always 10 clips: a round is as long as the actor's
                  // approved clips allow.
                  'trivia.same_clips_head_to_head'.tr(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13.5,
                    height: 1.3,
                  ),
                ),
                if (challenge.participants.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _ParticipantAvatars(challenge: challenge),
                ],
              ],
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: bottomSafe + 20,
          child: _PlayButton(joining: joining, onTap: onPlay),
        ),
      ],
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) =>
                ColoredBox(color: AppColors.surfaceVariant),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
            child: const ColoredBox(color: Color(0x66000000)),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.background.withValues(alpha: 0.67),
                  AppColors.background,
                ],
                stops: const [0.0, 0.8],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwordsBadge extends StatelessWidget {
  const _SwordsBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary,
      ),
      child: const Icon(CupertinoIcons.bolt_fill, color: Colors.white, size: 40),
    );
  }
}

class _ScoreToBeat extends StatelessWidget {
  const _ScoreToBeat({required this.score});
  final int score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(
            'trivia.score_to_beat'.tr().toUpperCase(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$score',
            style: const TextStyle(
              color: AppColors.rating,
              fontSize: 40,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ParticipantAvatars extends StatelessWidget {
  const _ParticipantAvatars({required this.challenge});
  final ChallengeEntity challenge;

  @override
  Widget build(BuildContext context) {
    final shown = challenge.participants.take(5).toList();
    final extra = challenge.participants.length - shown.length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final p in shown)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: _MiniAvatar(url: p.avatar, name: p.username),
          ),
        if (extra > 0)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 6),
            child: Text(
              '+$extra',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({required this.url, required this.name});
  final String url;
  final String name;

  @override
  Widget build(BuildContext context) {
    const size = 34.0;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surface,
      ),
      child: ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: ColoredBox(
            color: AppColors.surfaceVariant,
            child: url.trim().isEmpty
                ? Center(
                    child: Text(
                      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.joining, required this.onTap});
  final bool joining;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: joining ? null : onTap,
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(4),
        ),
        child: joining
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(CupertinoIcons.play_fill,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'trivia.play_challenge'.tr(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CircularProgressIndicator(color: AppColors.primary),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({this.message, this.onRetry});
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.link,
                color: AppColors.textHint, size: 46),
            const SizedBox(height: 16),
            Text(
              message?.isNotEmpty == true
                  ? message!
                  : 'trivia.challenge_not_found'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryLight,
                ),
                child: Text('general.retry'.tr()),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
              ),
              child: Text('general.close'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
