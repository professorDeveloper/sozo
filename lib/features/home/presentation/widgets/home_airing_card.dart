import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';

/// The way into the airing calendar, on an AniList Home.
///
/// The calendar existed and nothing on Home said so: an AniList viewer got
/// three generic "explore" chips in its place. This shows what the calendar
/// is for before it is opened — the next episode to air, counting down, and
/// what else lands in the next day — and opens it on tap.
class HomeAiringCard extends StatefulWidget {
  const HomeAiringCard({super.key});

  @override
  State<HomeAiringCard> createState() => _HomeAiringCardState();
}

class _HomeAiringCardState extends State<HomeAiringCard>
    with SingleTickerProviderStateMixin {
  /// Airings in the next day, soonest first; null while loading.
  List<AnilistScheduledAiring>? _next;
  bool _failed = false;
  Timer? _tick;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _load();
    // Minutes are the countdown's unit, so a minute is its refresh.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      final next = _next;
      if (next != null && next.isNotEmpty && _secondsTo(next.first) <= 0) {
        _load(); // the one counted down to has aired: move on
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final now = DateTime.now();
      final list = await getIt<AnilistService>().api.airingSchedule(
        from: now,
        to: now.add(const Duration(hours: 24)),
      );
      final upcoming = [
        for (final a in list)
          if (a.airingAt * 1000 > now.millisecondsSinceEpoch) a,
      ]..sort((a, b) => a.airingAt.compareTo(b.airingAt));
      if (mounted) {
        setState(() {
          _next = upcoming;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  static int _secondsTo(AnilistScheduledAiring a) =>
      a.airingAt - DateTime.now().millisecondsSinceEpoch ~/ 1000;

  static String _countdown(int seconds) {
    if (seconds < 60) return 'home.airing_now'.tr();
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return h > 0
        ? 'home.airing_in_hm'.tr(args: ['$h', '$m'])
        : 'home.airing_in_m'.tr(args: ['$m']);
  }

  @override
  Widget build(BuildContext context) {
    final next = _next;
    final first = (next != null && next.isNotEmpty) ? next.first : null;
    final covers = [
      for (final a in (next ?? const <AnilistScheduledAiring>[]).take(4))
        if (a.media.coverImage != null) a.media.coverImage!,
    ];
    const accent = Color(0xFF3DB4F2); // AniList blue

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/anilist/calendar'),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.22),
                  const Color(0xFF7C4DFF).withValues(alpha: 0.14),
                  AppColors.surface,
                ],
                stops: const [0, 0.45, 1],
              ),
              border: Border.all(color: accent.withValues(alpha: 0.28)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            FadeTransition(
                              opacity: Tween(
                                begin: 0.35,
                                end: 1.0,
                              ).animate(_pulse),
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFF4D6D),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'home.airing_on_air'.tr(),
                              style: const TextStyle(
                                color: Color(0xFFFF4D6D),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'home.airing_title'.tr(),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (first != null) ...[
                          Text(
                            'home.airing_next'.tr(
                              args: [
                                first.media.displayTitle,
                                '${first.episode}',
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.schedule_rounded,
                                size: 15,
                                color: accent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _countdown(_secondsTo(first)),
                                style: const TextStyle(
                                  color: accent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  'home.airing_today_count'.tr(
                                    args: ['${next!.length}'],
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ] else
                          Text(
                            _failed || next != null
                                ? 'home.airing_hint'.tr()
                                : 'home.airing_loading'.tr(),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _CoverStack(covers: covers),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Up to three covers fanned like cards, or a calendar glyph without them.
class _CoverStack extends StatelessWidget {
  const _CoverStack({required this.covers});
  final List<String> covers;

  @override
  Widget build(BuildContext context) {
    if (covers.isEmpty) {
      return Container(
        width: 64,
        height: 84,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.calendar_month_rounded,
          color: Color(0xFF3DB4F2),
          size: 30,
        ),
      );
    }
    final shown = covers.take(3).toList();
    return SizedBox(
      width: 64 + (shown.length - 1) * 16,
      height: 92,
      child: Stack(
        children: [
          for (var i = shown.length - 1; i >= 0; i--)
            Positioned(
              left: i * 16.0,
              top: i * 4.0,
              child: Transform.rotate(
                angle: (i - (shown.length - 1) / 2) * 0.06,
                child: Container(
                  width: 60,
                  height: 84,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: CachedNetworkImage(
                    imageUrl: shown[i],
                    fit: BoxFit.cover,
                    memCacheWidth: 180,
                    errorWidget: (_, _, _) => Container(color: Colors.white10),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
