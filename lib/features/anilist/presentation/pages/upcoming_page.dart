import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';
import 'package:soplay/features/anilist/presentation/controllers/anilist_library_controller.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_entry_sheet.dart';

/// When the next episode of everything you follow actually airs.
///
/// Built from the AniList library rather than a global airing schedule: a list
/// of every anime airing this week is a magazine, whereas "yours, soonest
/// first" is a thing to act on.
class UpcomingPage extends StatefulWidget {
  const UpcomingPage({super.key, this.showAppBar = true, this.controller});

  final bool showAppBar;
  final AnilistLibraryController? controller;

  @override
  State<UpcomingPage> createState() => _UpcomingPageState();
}

class _UpcomingPageState extends State<UpcomingPage> {
  final AnilistService _service = getIt<AnilistService>();
  late final AnilistLibraryController _controller;
  late final bool _ownsController = widget.controller == null;

  /// Redraws the countdowns.
  ///
  /// Every 30s, not every second: the labels below are rendered in hours and
  /// minutes, so a per-second tick would rebuild the whole list sixty times to
  /// change nothing.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ?? AnilistLibraryController(service: _service);
    _controller.addListener(_onChange);
    _service.addListener(_onChange);
    _controller.load();
    _ticker = Timer.periodic(
      const Duration(seconds: 30),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller.removeListener(_onChange);
    _service.removeListener(_onChange);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final body = !_service.isConnected
        ? AnilistConnectPrompt(
            message: 'anilist.upcoming_connect_prompt'.tr(),
            actionLabel: 'anilist.connect'.tr(),
            busy: _service.linking,
            onConnect: _service.beginLink,
          )
        : _buildList(context);

    if (!widget.showAppBar) return body;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Text(
          'anilist.upcoming_title'.tr(),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: body,
    );
  }

  Widget _buildList(BuildContext context) {
    final entries = _controller.upcoming;

    if (_controller.loading && entries.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: kAnilistBlue, strokeWidth: 2.5),
      );
    }

    Future<void> refresh() => _controller.load(force: true);

    if (entries.isEmpty) {
      // A load failure and an empty schedule are not the same state: the old
      // shape put the error text under a "nothing airs" icon with no way back.
      final error = _controller.error;
      return RefreshIndicator(
        color: kAnilistBlue,
        backgroundColor: AppColors.surface,
        onRefresh: refresh,
        child: AnilistScrollableMessage(
          message: AnilistStateMessage(
            icon: error != null
                ? Icons.cloud_off_rounded
                : Icons.event_available_rounded,
            text: error ?? 'anilist.upcoming_empty'.tr(),
            actionLabel: error == null ? null : 'anilist.retry'.tr(),
            onAction: error == null ? null : refresh,
          ),
        ),
      );
    }

    // Grouped by calendar day so the list reads as a schedule rather than a
    // flat run of timestamps.
    final groups = <String, List<AnilistListEntry>>{};
    for (final entry in entries) {
      groups
          .putIfAbsent(_dayKey(entry.media.nextAiring!.airsAt), () => [])
          .add(entry);
    }

    return RefreshIndicator(
      color: kAnilistBlue,
      backgroundColor: AppColors.surface,
      onRefresh: refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
        children: [
          for (final group in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 12, 2, 10),
              child: Text(
                _dayLabel(context, group.value.first.media.nextAiring!.airsAt),
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            for (final entry in group.value) ...[
              _UpcomingCard(
                entry: entry,
                onTap: () => AnilistEntrySheet.show(
                  context,
                  entryId: entry.id,
                  controller: _controller,
                ),
              ),
              const SizedBox(height: 9),
            ],
          ],
        ],
      ),
    );
  }

  static String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  String _dayLabel(BuildContext context, DateTime airsAt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(airsAt.year, airsAt.month, airsAt.day);
    final delta = day.difference(today).inDays;
    if (delta <= 0) return 'anilist.today'.tr().toUpperCase();
    if (delta == 1) return 'anilist.tomorrow'.tr().toUpperCase();
    return DateFormat.MMMEd(
      context.locale.toString(),
    ).format(airsAt).toUpperCase();
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.entry, required this.onTap});

  final AnilistListEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final airing = entry.media.nextAiring!;
    final left = airing.timeLeft;
    final aired = airing.hasAired;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              AnilistCover(url: entry.media.coverImage, width: 46, radius: 8),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.media.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        AnilistChip(
                          label: 'anilist.episode_n'.tr(
                            args: ['${airing.episode}'],
                          ),
                          icon: Icons.play_arrow_rounded,
                        ),
                        AnilistChip(
                          label: aired
                              ? 'anilist.aired'.tr()
                              : _countdown(left),
                          icon: aired
                              ? Icons.check_rounded
                              : Icons.schedule_rounded,
                          color: aired
                              ? AppColors.success
                              : AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                DateFormat.Hm(context.locale.toString()).format(airing.airsAt),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Coarse on purpose: "3 kun" is more useful than "3d 4h 12m", and the
  /// precise time is already shown to the right.
  static String _countdown(Duration left) {
    if (left.inDays >= 1) return 'anilist.in_days'.tr(args: ['${left.inDays}']);
    if (left.inHours >= 1) {
      return 'anilist.in_hours'.tr(args: ['${left.inHours}']);
    }
    final minutes = left.inMinutes < 1 ? 1 : left.inMinutes;
    return 'anilist.in_minutes'.tr(args: ['$minutes']);
  }
}
