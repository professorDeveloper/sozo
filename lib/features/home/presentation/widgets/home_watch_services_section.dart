import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/analytics/analytics.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/tv/tv.dart';
import 'package:soplay/features/home/domain/home_rail.dart';

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
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(widget.icon, size: 18, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.body,
                        style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _answer(accepted: false),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                  ),
                  child: Text('home.suggest_no'.tr()),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: () => _answer(accepted: true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: Text('home.suggest_add'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
