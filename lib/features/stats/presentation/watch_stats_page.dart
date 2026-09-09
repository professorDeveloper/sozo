import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/stats/data/watch_stats_store.dart';

/// What has been watched, since counting began.
///
/// ## The honesty this screen has to carry
///
/// It cannot know anything from before the feature shipped: history is a
/// rolling fifty-item window holding positions, not a ledger of time. So the
/// total is stamped with the date counting started, and the screen says so
/// rather than presenting a number that looks like a lifetime and is not.
///
/// ## Nothing here is a goal
///
/// No targets, no badges, no "you are below average". Time spent watching is
/// not an achievement and framing it as one turns a page somebody opened out of
/// curiosity into a nudge to watch more. It reports; it does not encourage.
class WatchStatsPage extends StatefulWidget {
  const WatchStatsPage({super.key});

  static void open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const WatchStatsPage()),
      );

  @override
  State<WatchStatsPage> createState() => _WatchStatsPageState();
}

class _WatchStatsPageState extends State<WatchStatsPage> {
  final WatchStatsStore _store = WatchStatsStore();

  /// The window the bar chart covers. Two weeks fits on a phone without the
  /// bars becoming lines, and is long enough for a pattern to be visible.
  static const int _chartDays = 14;

  @override
  Widget build(BuildContext context) {
    final total = _store.totalSeconds;
    final since = _store.since;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Text('stats.title'.tr()),
      ),
      // Pull to refresh, because these numbers are read from Hive at build and
      // the player writes them from another page: coming back from an episode
      // shows the totals from before it unless something rebuilds. A refresh
      // that only calls setState looks like it does nothing, so the indicator
      // is held briefly — otherwise the gesture completes before the eye can
      // register that anything happened.
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        onRefresh: () async {
          await Future<void>.delayed(const Duration(milliseconds: 350));
          if (mounted) setState(() {});
        },
        child: total == 0
          ? _empty()
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                MediaQuery.paddingOf(context).bottom + 24,
              ),
              children: [
                _Headline(seconds: total, since: since),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _StatBox(
                        icon: Icons.check_circle_outline_rounded,
                        value: '${_store.completed}',
                        label: 'stats.completed'.tr(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatBox(
                        icon: Icons.local_fire_department_outlined,
                        value: '${_store.streakDays}',
                        label: 'stats.streak'.tr(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _SectionTitle('stats.last_days'.tr(args: ['$_chartDays'])),
                const SizedBox(height: 10),
                _DayChart(byDay: _store.byDay, days: _chartDays),
                const SizedBox(height: 24),
                if (_store.byProvider.isNotEmpty) ...[
                  _SectionTitle('stats.by_source'.tr()),
                  const SizedBox(height: 10),
                  _ProviderBreakdown(byProvider: _store.byProvider),
                ],
              ],
            ),
      ),
    );
  }

  /// Scrollable even though it fits, so the refresh gesture works here too —
  /// and this is exactly where somebody pulls, having just watched something
  /// and found the page still empty.
  Widget _empty() => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(32, 60, 32, 32),
        children: [
          Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.bar_chart_rounded,
              size: 52,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 14),
            Text(
              'stats.empty_title'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'stats.empty_subtitle'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
          ),
        ],
      );
}

/// Hours and minutes, spelled out, with what they are the total of.
class _Headline extends StatelessWidget {
  const _Headline({required this.seconds, required this.since});

  final int seconds;
  final DateTime? since;

  @override
  Widget build(BuildContext context) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'stats.watched'.tr(),
            style: const TextStyle(color: AppColors.textHint, fontSize: 12.5),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$hours',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'stats.hours_short'.tr(),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$minutes',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                'stats.minutes_short'.tr(),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (since != null) ...[
            const SizedBox(height: 10),
            // The whole reason this line exists: a total that started counting
            // last Tuesday must not read as a lifetime.
            Text(
              'stats.since'.tr(
                args: [DateFormat.yMMMd(context.locale.toString()).format(since!)],
              ),
              style: const TextStyle(color: AppColors.textHint, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: AppColors.textHint, fontSize: 11.5),
            ),
          ],
        ),
      );
}

/// A bar per day, scaled to the busiest day in the window.
///
/// Scaled to the window rather than to an absolute hour, because the shape is
/// the information: somebody who watches twenty minutes a day should see an
/// even row, not a flat line under a scale set for somebody else.
class _DayChart extends StatelessWidget {
  const _DayChart({required this.byDay, required this.days});

  final Map<String, int> byDay;
  final int days;

  static String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final values = [
      for (var i = days - 1; i >= 0; i--)
        byDay[_key(now.subtract(Duration(days: i)))] ?? 0,
    ];
    final peak = values.fold<int>(0, (m, v) => v > m ? v : m);

    return SizedBox(
      height: 96,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++) ...[
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    // A day with nothing still draws a sliver, so the row
                    // reads as fourteen days rather than as a chart with
                    // holes in it.
                    height: peak == 0
                        ? 3
                        : (3 + 73 * (values[i] / peak)).toDouble(),
                    decoration: BoxDecoration(
                      color: values[i] == 0
                          ? Colors.white.withValues(alpha: 0.07)
                          : AppColors.primary.withValues(
                              alpha: 0.45 + 0.55 * (values[i] / peak),
                            ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Only the ends are labelled: fourteen dates across a phone
                  // is a grey smear, and the two that matter are "when this
                  // starts" and "today".
                  SizedBox(
                    height: 12,
                    child: i == 0 || i == values.length - 1
                        ? Text(
                            '${now.subtract(Duration(days: values.length - 1 - i)).day}',
                            style: const TextStyle(
                              color: AppColors.textHint,
                              fontSize: 9.5,
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ),
            if (i < values.length - 1) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

/// Where the time went, longest first.
class _ProviderBreakdown extends StatelessWidget {
  const _ProviderBreakdown({required this.byProvider});

  final Map<String, int> byProvider;

  /// Beyond this the list stops being a summary. The tail is real but it is
  /// not what somebody opened this page to read.
  static const int _max = 6;

  @override
  Widget build(BuildContext context) {
    final rows = byProvider.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = rows.take(_max).toList();
    final peak = top.isEmpty ? 0 : top.first.value;

    return Column(
      children: [
        for (final row in top)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 92,
                  child: Text(
                    row.key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: peak == 0 ? 0 : row.value / peak,
                      minHeight: 6,
                      backgroundColor: Colors.white.withValues(alpha: 0.06),
                      valueColor: AlwaysStoppedAnimation(AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 52,
                  child: Text(
                    _short(row.value),
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _short(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      );
}
