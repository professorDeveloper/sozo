import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/kaizoku_colors.dart';
import 'package:soplay/features/trivia/domain/entities/cast_person_entity.dart';
import 'package:soplay/features/trivia/presentation/bloc/cast/cast_bloc.dart';
import 'package:soplay/features/trivia/presentation/bloc/cast/cast_event.dart';
import 'package:soplay/features/trivia/presentation/bloc/cast/cast_state.dart';
import 'package:soplay/features/trivia/presentation/widgets/buff_empty_panel.dart';
import 'package:soplay/features/trivia/presentation/widgets/popular_cast_grid.dart';

/// Fan-Test entry surface: a pinned glass search bar over a "Popular now" grid
/// that becomes debounced as-you-type results. Tapping a card flies its photo
/// into the Actor Hero screen. Only live actors (kind 'person') are surfaced.
class CastPickerPage extends StatelessWidget {
  const CastPickerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CastBloc>(
      create: (_) => getIt<CastBloc>()..add(const CastStarted()),
      child: const _CastPickerView(),
    );
  }
}

class _CastPickerView extends StatefulWidget {
  const _CastPickerView();

  @override
  State<_CastPickerView> createState() => _CastPickerViewState();
}

class _CastPickerViewState extends State<_CastPickerView> {
  final TextEditingController _controller = TextEditingController();

  /// Real content height of [_GlassHeader], excluding the top safe area which
  /// is added separately. Re-derived after the anime toggle was removed and
  /// again after the field/caption were brought onto the shipped scale:
  ///   top pad 12 + field 46 + gap 12 + caption (15 × 1.1 line height) + bottom
  ///   pad 12 = 100.15 at the owner's textScale 1.1 (98.5 at scale 1.0).
  /// 102 leaves ~2px so the first grid row never tucks under the blur.
  static const double _headerHeight = 102;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openActor(CastPersonEntity person) {
    context.push('/trivia/actor', extra: person);
  }

  @override
  Widget build(BuildContext context) {
    final topSafe = MediaQuery.paddingOf(context).top;
    final contentTop = topSafe + _headerHeight;

    return Scaffold(
      backgroundColor: KaizokuColors.background,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: BlocBuilder<CastBloc, CastState>(
              builder: (context, state) => _Body(
                state: state,
                topPadding: contentTop,
                onTapPerson: _openActor,
              ),
            ),
          ),
          _GlassHeader(
            topSafe: topSafe,
            controller: _controller,
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.state,
    required this.topPadding,
    required this.onTapPerson,
  });

  final CastState state;
  final double topPadding;
  final void Function(CastPersonEntity) onTapPerson;

  @override
  Widget build(BuildContext context) {
    // 12px gutter — the app's 3-column grid gutter. This is a pushed route,
    // not a tab root, so it clears the safe area only (no floating nav pill).
    final padding = EdgeInsets.fromLTRB(
      12,
      topPadding,
      12,
      MediaQuery.paddingOf(context).bottom + 24,
    );
    final searching = state.isSearchActive;

    switch (state.status) {
      case CastStatus.initial:
      case CastStatus.loadingPopular:
      case CastStatus.searching:
        return CastGridSkeleton(padding: padding);

      case CastStatus.error:
        return _CenteredNotice(
          topPadding: topPadding,
          icon: CupertinoIcons.wifi_slash,
          title: 'trivia.something_wrong'.tr(),
          subtitle: state.message,
          onRetry: () {
            final bloc = context.read<CastBloc>();
            if (searching) {
              bloc.add(CastQueryChanged(state.query));
            } else {
              bloc.add(const CastStarted());
            }
          },
        );

      case CastStatus.empty:
        return _CenteredNotice(
          topPadding: topPadding,
          icon: CupertinoIcons.search,
          title: 'trivia.no_results'.tr(),
          subtitle: 'trivia.no_results_hint'.tr(),
        );

      case CastStatus.popular:
        // Zero approved clips means zero playable actors. Saying so beats a
        // blank page under the glass header, and there is nothing to retry.
        if (state.popular.isEmpty) {
          return _CenteredNotice(
            topPadding: topPadding,
            icon: CupertinoIcons.film,
            title: 'trivia.no_actors_yet'.tr(),
            subtitle: 'trivia.no_actors_yet_body'.tr(),
            onRetry: () => context.read<CastBloc>().add(const CastStarted()),
          );
        }
        return PopularCastGrid(
          people: state.popular,
          onTapPerson: onTapPerson,
          padding: padding,
        );

      case CastStatus.results:
        return PopularCastGrid(
          people: state.results,
          highlight: state.query,
          onTapPerson: onTapPerson,
          padding: padding,
        );
    }
  }
}

/// The pinned, frosted search header floating over the grid.
class _GlassHeader extends StatelessWidget {
  const _GlassHeader({required this.topSafe, required this.controller});

  final double topSafe;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            padding: EdgeInsets.fromLTRB(16, topSafe + 12, 16, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  KaizokuColors.background.withValues(alpha: 0.92),
                  KaizokuColors.background.withValues(alpha: 0.55),
                ],
              ),
              border: Border(
                bottom: BorderSide(
                  color: KaizokuColors.border.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SearchField(controller: controller),
                const SizedBox(height: 12),
                const _ContextCaption(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CastBloc, CastState>(
      buildWhen: (a, b) => a.query.isEmpty != b.query.isEmpty,
      builder: (context, state) {
        final hasText = state.query.isNotEmpty;
        // Matches the shipped search field (`search_header.dart`): 46 high,
        // radius 14, translucent surface, hairline white border.
        return Container(
          height: 46,
          decoration: BoxDecoration(
            color: KaizokuColors.surface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              const Icon(
                CupertinoIcons.search,
                color: KaizokuColors.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  cursorColor: KaizokuColors.primary,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(
                    color: KaizokuColors.textPrimary,
                    fontSize: 15,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'trivia.search_cast_hint'.tr(),
                    hintStyle: const TextStyle(
                      color: KaizokuColors.textHint,
                      fontSize: 15,
                    ),
                  ),
                  onChanged: (v) =>
                      context.read<CastBloc>().add(CastQueryChanged(v)),
                ),
              ),
              if (hasText)
                GestureDetector(
                  onTap: () {
                    controller.clear();
                    context.read<CastBloc>().add(const CastCleared());
                    FocusScope.of(context).unfocus();
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(
                      CupertinoIcons.clear_circled_solid,
                      color: KaizokuColors.textSecondary,
                      size: 20,
                    ),
                  ),
                )
              else
                const SizedBox(width: 12),
            ],
          ),
        );
      },
    );
  }
}

class _ContextCaption extends StatelessWidget {
  const _ContextCaption();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CastBloc, CastState>(
      buildWhen: (a, b) =>
          a.isSearchActive != b.isSearchActive || a.status != b.status,
      builder: (context, state) {
        final String text;
        if (!state.isSearchActive) {
          text = 'trivia.popular_now'.tr();
        } else if (state.status == CastStatus.results) {
          text = 'trivia.results'.tr();
        } else {
          text = 'trivia.searching'.tr();
        }
        // Sub-section header scale (15 / w800 / textPrimary) — sentence case,
        // no letterSpacing, per the shipped section-header idiom.
        return Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: KaizokuColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        );
      },
    );
  }
}

/// Positions the shared [BuffEmptyPanel] under the pinned glass header. The
/// panel itself (radius 24 / blur 20 / icon circle 64) now lives in
/// `buff_empty_panel.dart` so the hub and the game screen speak with the same
/// voice.
class _CenteredNotice extends StatelessWidget {
  const _CenteredNotice({
    required this.topPadding,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onRetry,
  });

  final double topPadding;
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, topPadding + 24, 24, bottomSafe + 64),
      child: Center(
        child: SingleChildScrollView(
          child: BuffEmptyPanel(
            icon: icon,
            title: title,
            body: subtitle,
            onAction: onRetry,
          ),
        ),
      ),
    );
  }
}
