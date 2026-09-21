import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/analytics/analytics.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/tv/tv.dart';
import 'package:soplay/features/home/domain/home_rail.dart';
import 'package:soplay/features/watch_services/domain/entities/watch_service_entity.dart';
import 'package:soplay/features/watch_services/presentation/bloc/watch_services/watch_services_bloc.dart';

/// The way in to the streaming line-up, once somebody has asked for it.
///
/// One row, not a rail of logos. A rail would have to fetch a hundred and
/// thirty marks to fill itself before anybody had shown any interest, and the
/// answer it gives — which services carry what, here — is a page, not a shelf.
/// This costs nothing until it is tapped.
///
/// It carries its own way off Home, because a band that can only be removed
/// from a settings screen somewhere else is a band people put up with.
class HomeWatchServicesSection extends StatelessWidget {
  const HomeWatchServicesSection({super.key});

  @override
  Widget build(BuildContext context) {
    void open() {
      getIt<Analytics>().track(
        AnalyticsEvent.watchServicesOpened,
        props: const {'from': 'home'},
      );
      context.push('/watch-services');
    }

    Future<void> remove() async {
      final hive = getIt<HiveService>();
      await hive.hideHomeRail(HomeRail.watchServices.id);
      getIt<Analytics>().track(
        AnalyticsEvent.homeRailRemoved,
        props: {'rail': HomeRail.watchServices.id},
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('home.removed_undo_hint'.tr())));
    }

    final card = Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              Icons.subscriptions_rounded,
              size: 20,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'watch.services_title'.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'watch.services_entry_hint'.tr(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 11.5,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          // The way off Home, on the thing itself.
          PopupMenuButton<int>(
            tooltip: 'home.remove_from_home'.tr(),
            icon: const Icon(
              Icons.more_vert_rounded,
              size: 18,
              color: AppColors.textHint,
            ),
            color: AppColors.surfaceVariant,
            onSelected: (_) => remove(),
            itemBuilder: (context) => [
              PopupMenuItem<int>(
                value: 0,
                child: Row(
                  children: [
                    const Icon(Icons.close_rounded, size: 18),
                    const SizedBox(width: 10),
                    Flexible(child: Text('home.remove_from_home'.tr())),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: isTvPlatform
          ? TvFocusable(onPressed: open, borderRadius: 14, child: card)
          : HoverTap(
              onTap: open,
              borderRadius: 14,
              scale: 1.01,
              haptic: true,
              child: card,
            ),
    );
  }
}

/// The app asking for room on somebody's Home screen. Once, ever.
///
/// Both answers are final and both are recorded, which is the point of asking
/// at all: a suggestion that comes back after "no thanks" is not a suggestion.
/// The yes is reversible from the band itself and from Appearance; the no is
/// reversible from Appearance. Neither is reversed by the app.
///
/// ## Why it is this small
///
/// It started as a full-width block with a filled button the size of a Play
/// control, above the hero, and it read as an advertisement rather than as a
/// question — the loudest thing on a screen it was interrupting. A suggestion
/// is allowed one line of explanation and two words of assent. The buttons are
/// text, not fills: the accent in this app means "this is the action", and
/// nothing here is the action.
///
/// The marks are the argument. "Streaming services" is an abstraction; four
/// logos somebody recognises is the feature, and showing them is also what
/// makes the page instant when it is opened, because the answer is already in
/// the singleton by then.
class HomeSuggestionCard extends StatefulWidget {
  const HomeSuggestionCard({
    super.key,
    required this.rail,
    required this.title,
    required this.body,
    required this.icon,
    required this.onAnswered,
  });

  final HomeRail rail;
  final String title;
  final String body;
  final IconData icon;
  final VoidCallback onAnswered;

  @override
  State<HomeSuggestionCard> createState() => _HomeSuggestionCardState();
}

class _HomeSuggestionCardState extends State<HomeSuggestionCard> {
  @override
  void initState() {
    super.initState();
    // Counted where it is put, not where it is built: Home rebuilds on every
    // source switch and every pull, and an event per rebuild would make the
    // question look a hundred times more popular than it was ever asked.
    getIt<Analytics>().track(
      AnalyticsEvent.homeSuggestionShown,
      props: {'rail': widget.rail.id},
    );
    // The marks, and a warm cache for the page behind them. Only while the
    // question is unanswered, so an install that said no never asks again and
    // never fetches again either.
    final bloc = getIt<WatchServicesBloc>();
    if (bloc.state.status == WatchServicesStatus.initial) {
      bloc.add(const WatchServicesLoad());
    }
  }

  Future<void> _answer({required bool accepted}) async {
    await getIt<HiveService>().answerHomeSuggestion(
      widget.rail.id,
      accepted: accepted,
    );
    getIt<Analytics>().track(
      accepted
          ? AnalyticsEvent.homeSuggestionAccepted
          : AnalyticsEvent.homeSuggestionDismissed,
      props: {'rail': widget.rail.id},
    );
    widget.onAnswered();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 11, 8, 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BlocBuilder<WatchServicesBloc, WatchServicesState>(
                  bloc: getIt<WatchServicesBloc>(),
                  builder: (context, state) => _ServiceMarks(
                    services: state.services,
                    fallback: widget.icon,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _QuietAction(
                  label: 'home.suggest_no'.tr(),
                  color: AppColors.textHint,
                  onTap: () => _answer(accepted: false),
                ),
                const SizedBox(width: 2),
                _QuietAction(
                  label: 'home.suggest_add'.tr(),
                  color: AppColors.primary,
                  bold: true,
                  onTap: () => _answer(accepted: true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Two words, at the weight an answer deserves.
class _QuietAction extends StatelessWidget {
  const _QuietAction({
    required this.label,
    required this.color,
    required this.onTap,
    this.bold = false,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool bold;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      foregroundColor: color,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      minimumSize: const Size(0, 34),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
      ),
    ),
  );
}

/// Four marks, overlapping, in the order the country actually uses them.
///
/// Overlapping rather than in a row because the point is "these", not "four of
/// these" — the same shorthand a stack of faces uses for a group. They keep
/// the square-with-a-generous-radius shape the service grid gives them, so the
/// thing being offered looks like the thing that arrives.
class _ServiceMarks extends StatelessWidget {
  const _ServiceMarks({required this.services, required this.fallback});

  final List<WatchServiceEntity> services;
  final IconData fallback;

  static const double _size = 30;
  static const double _overlap = 10;
  static const int _max = 4;

  @override
  Widget build(BuildContext context) {
    final shown = services.take(_max).toList();
    if (shown.isEmpty) {
      // Offline, or the answer has not landed yet. The question still stands;
      // it just has to make its case without the logos.
      return Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(fallback, size: 18, color: AppColors.primary),
      );
    }

    final dpr = MediaQuery.devicePixelRatioOf(context);
    return SizedBox(
      width: _size + (shown.length - 1) * (_size - _overlap),
      height: _size,
      child: Stack(
        children: [
          // Reversed, so the first service is painted last and sits on top:
          // TMDB orders these by how much they are used, and the one in front
          // should be the one most people recognise.
          for (final (i, s) in shown.indexed.toList().reversed)
            PositionedDirectional(
              start: i * (_size - _overlap),
              child: Container(
                width: _size,
                height: _size,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(_size * 0.235),
                  // A hairline of the card behind it, so overlapping marks
                  // stay separate instead of merging into one dark blob.
                  border: Border.all(color: AppColors.surface, width: 1.5),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_size * 0.235 - 1.5),
                  child: s.logo == null
                      ? const SizedBox.shrink()
                      : CachedNetworkImage(
                          imageUrl: s.logo!,
                          fit: BoxFit.cover,
                          memCacheWidth: (_size * dpr).round(),
                          fadeInDuration: const Duration(milliseconds: 180),
                          errorWidget: (_, _, _) => const SizedBox.shrink(),
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
