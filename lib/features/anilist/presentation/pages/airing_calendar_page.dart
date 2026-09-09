import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/anilist/data/airing_reminders.dart';
import 'package:soplay/features/anilist/data/anilist_api.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';
import 'package:soplay/features/anilist/presentation/controllers/airing_calendar_controller.dart';
import 'package:soplay/features/anilist/presentation/controllers/anilist_library_controller.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_entry_sheet.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_logo.dart';

/// What airs over the next two weeks, across all of AniList.
///
/// The complement to Upcoming, which is deliberately narrow — only the shows
/// you already follow. This is the wide view, with a filter back down to yours,
/// so discovering a new season doesn't mean leaving the app.
///
/// Works signed out: the schedule is public. Connecting only adds the "on your
/// list" marks, the filter, and the per-entry actions.
class AiringCalendarPage extends StatefulWidget {
  const AiringCalendarPage({
    super.key,
    this.showAppBar = true,
    this.controller,
  });

  final bool showAppBar;

  /// The library, when a host already holds one. Lent rather than built here so
  /// a "+1" made on another AniList screen is reflected by the marks on this
  /// one, and so opening the calendar does not re-fetch the whole collection.
  final AnilistLibraryController? controller;

  @override
  State<AiringCalendarPage> createState() => _AiringCalendarPageState();
}

class _AiringCalendarPageState extends State<AiringCalendarPage>
    with WidgetsBindingObserver {
  final AnilistService _service = getIt<AnilistService>();
  late final AiringCalendarController _calendar;
  late final AnilistLibraryController _library;
  late final bool _ownsLibrary = widget.controller == null;

  late final PageController _pages;
  final ScrollController _strip = ScrollController();

  /// Redraws what the clock decides: the aired fade, the time pill colour and
  /// the "now" rule all move on their own, and nothing else on this page would
  /// notice. Also the cheapest place to catch midnight passing.
  Timer? _ticker;

  bool _libraryLoading = false;
  String? _libraryError;

  @override
  void initState() {
    super.initState();
    _calendar = AiringCalendarController(service: _service);
    _library = widget.controller ?? AnilistLibraryController(service: _service);
    _pages = PageController(initialPage: _calendar.selectedIndex);

    _calendar.addListener(_onChange);
    _library.addListener(_onLibraryChange);
    _service.addListener(_onServiceChange);
    WidgetsBinding.instance.addObserver(this);

    _calendar.setLibrary(_library.entries);
    _calendar.load();
    if (_service.isConnected) _library.load();

    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      _calendar.syncToToday();
      setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _centreStrip(jump: true),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _calendar.removeListener(_onChange);
    _library.removeListener(_onLibraryChange);
    _service.removeListener(_onServiceChange);
    _pages.dispose();
    _strip.dispose();
    _calendar.dispose();
    if (_ownsLibrary) _library.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _calendar.syncToToday();
    if (mounted) setState(() {});
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    _syncPager();
  }

  /// Lays down reminders whenever the library changes.
  ///
  /// Driven off the library rather than the calendar's day pages: the reminder
  /// is for what YOU follow, and the calendar's window is everything.
  void _syncReminders() {
    if (!_service.isConnected) return;
    unawaited(getIt<AiringReminders>().sync(_library.entries));
  }

  void _onLibraryChange() {
    // setLibrary notifies the calendar, which this page already listens to, so
    // rebuilding again here would double every optimistic write the library
    // makes — and the library notifies on each one.
    if (_calendar.setLibrary(_library.entries)) return;
    if (_library.loading == _libraryLoading &&
        _library.error == _libraryError) {
      return;
    }
    _libraryLoading = _library.loading;
    _libraryError = _library.error;
    _syncReminders();
    _onChange();
  }

  void _onServiceChange() {
    if (_service.isConnected) {
      _library.load();
    } else {
      _calendar.setLibrary(const []);
    }
    _onChange();
  }

  void _syncPager() {
    if (!_pages.hasClients) return;
    final index = _calendar.selectedIndex;
    final current = (_pages.page ?? _pages.initialPage.toDouble()).round();
    if (current != index) {
      _pages.animateToPage(
        index,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
    _centreStrip();
  }

  /// Keeps the selected pill on screen. The strip runs a fortnight now, so the
  /// day being shown can easily sit past the end of it.
  void _centreStrip({bool jump = false}) {
    if (!_strip.hasClients) return;
    const extent = _DayStrip.pillWidth + _DayStrip.gap;
    final viewport = _strip.position.viewportDimension;
    final target =
        (_calendar.selectedIndex * extent +
                _DayStrip.padding +
                _DayStrip.pillWidth / 2 -
                viewport / 2)
            .clamp(0.0, _strip.position.maxScrollExtent);
    if ((target - _strip.offset).abs() < 1) return;
    if (jump) {
      _strip.jumpTo(target);
      return;
    }
    _strip.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        _DayStrip(controller: _calendar, scrollController: _strip),
        if (_service.isConnected) _MineFilter(controller: _calendar),
        _DayHeader(controller: _calendar),
        Expanded(
          child: PageView.builder(
            controller: _pages,
            itemCount: _calendar.days.length,
            onPageChanged: (i) => _calendar.select(_calendar.days[i]),
            itemBuilder: (context, i) => _buildDay(context, _calendar.days[i]),
          ),
        ),
      ],
    );

    if (!widget.showAppBar) return body;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Row(
          children: [
            const AnilistLogo(size: 20),
            const SizedBox(width: 9),
            Text(
              'anilist.calendar_title'.tr(),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          // Only offered while connected: a reminder is for what you follow,
          // and signed out there is no list to follow.
          if (_service.isConnected)
            IconButton(
              tooltip: getIt<AiringReminders>().enabled
                  ? 'anilist.reminders_on'.tr()
                  : 'anilist.reminders_off'.tr(),
              onPressed: _toggleReminders,
              icon: Icon(
                getIt<AiringReminders>().enabled
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
                color: getIt<AiringReminders>().enabled ? kAnilistBlue : null,
              ),
            ),
        ],
      ),
      body: body,
    );
  }

  Future<void> _toggleReminders() async {
    final reminders = getIt<AiringReminders>();
    final next = !reminders.enabled;
    await reminders.setEnabled(next);
    if (next) await reminders.sync(_library.entries);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next ? 'anilist.reminders_on'.tr() : 'anilist.reminders_off'.tr(),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildDay(BuildContext context, DateTime day) {
    if (_calendar.isPendingFor(day)) return const _DaySkeleton();

    Future<void> refresh() => _calendar.loadDay(day, force: true);
    final rows = _calendar.rowsFor(day);
    if (rows.isEmpty) return _buildEmpty(context, day, refresh);

    final nowAt = _nowMarker(day, rows);

    return RefreshIndicator(
      color: kAnilistBlue,
      backgroundColor: AppColors.surface,
      onRefresh: refresh,
      child: Column(
        children: [
          // A failed refresh over a day that still holds entries has nowhere
          // else to show: the list branch never reaches the empty state.
          if (_calendar.isStaleFor(day))
            _StaleBanner(
              message: _calendar.errorFor(day)!,
              onRetry: () => _calendar.loadDay(day, force: true),
            ),
          Expanded(
            child: ListView.separated(
              key: PageStorageKey<String>('anilist-day-${day.toIso8601String()}'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 9),
              itemBuilder: (context, i) {
                final row = rows[i];
                // The label is printed once per clock time. A column repeating
                // 18:00 down six rows is noise; the line is what carries them.
                final previous = i == 0 ? null : rows[i - 1].airing.airsAt;
                final at = row.airing.airsAt;
                final startsTime = previous == null ||
                    previous.hour != at.hour ||
                    previous.minute != at.minute;

                final card = _TimeRailRow(
                  at: at,
                  showTime: startsTime,
                  aired: row.airing.hasAired,
                  first: i == 0,
                  last: i == rows.length - 1,
                  child: _AiringCard(
                    row: row,
                    mine: _calendar.isMine(row.airing.media.id),
                    onTap: () => _openRow(row),
                  ),
                );
                if (i != nowAt) return card;
                return Column(
                  children: [
                    const _NowDivider(),
                    const SizedBox(height: 9),
                    card,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(
    BuildContext context,
    DateTime day,
    Future<void> Function() refresh,
  ) {
    final error = _calendar.errorFor(day);
    // Three cases, not two: nothing airs, nothing OF YOURS airs, and "your list
    // never loaded" — which the second would report as an empty week.
    final listFailed = _calendar.mineOnly && _library.error != null;
    final String message;
    if (error != null) {
      message = error;
    } else if (listFailed) {
      message = 'anilist.calendar_list_error'.tr();
    } else {
      message = _calendar.mineOnly && _calendar.hasAnyFor(day)
          ? 'anilist.calendar_empty_mine'.tr()
          : 'anilist.calendar_empty'.tr();
    }
    final failed = error != null || listFailed;
    final VoidCallback retry =
        listFailed ? () => _library.load(force: true) : refresh;

    return RefreshIndicator(
      color: kAnilistBlue,
      backgroundColor: AppColors.surface,
      onRefresh: refresh,
      child: AnilistScrollableMessage(
        message: AnilistStateMessage(
          icon: failed ? Icons.cloud_off_rounded : Icons.event_busy_rounded,
          text: message,
          actionLabel: failed ? 'anilist.retry'.tr() : null,
          onAction: failed ? retry : null,
        ),
      ),
    );
  }

  /// Where "now" falls in the day, or -1 when a rule would say nothing — any
  /// other day, or a day entirely behind or entirely ahead of this moment.
  int _nowMarker(DateTime day, List<AiringDayRow> rows) {
    if (day != _calendar.today) return -1;
    final index = rows.indexWhere((r) => !r.airing.hasAired);
    return index <= 0 ? -1 : index;
  }

  void _openRow(AiringDayRow row) {
    final media = row.airing.media;
    final entry = _library.entryForMedia(media.id);
    if (entry != null) {
      AnilistEntrySheet.show(context, entryId: entry.id, controller: _library);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _MediaActions(
        media: media,
        onAdd: _service.isConnected ? () => _addToPlanning(media) : null,
      ),
    );
  }

  Future<void> _addToPlanning(AnilistMedia media) async {
    final token = _service.token;
    if (token == null) return;
    final messenger = ScaffoldMessenger.of(context);
    String message;
    try {
      final saved = await _service.api.addToList(token: token, mediaId: media.id);
      // Re-read rather than patch a synthetic entry in: the mark on this card
      // is driven by the library, and AniList decides the entry's id.
      await _library.load(force: true);
      // null means the title was already there — which is what we see whenever
      // the library failed to load, so say so instead of claiming an add.
      message = saved == null
          ? 'anilist.calendar_already_on_list'.tr()
          : 'anilist.calendar_added_planning'.tr();
    } catch (e) {
      message = e is AnilistException
          ? e.message
          : 'anilist.calendar_add_failed'.tr();
    }
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

/// The day selector: yesterday, today, and a fortnight ahead.
class _DayStrip extends StatelessWidget {
  const _DayStrip({required this.controller, required this.scrollController});

  static const double pillWidth = 54;
  static const double gap = 8;
  static const double padding = 14;

  final AiringCalendarController controller;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final locale = context.locale.toString();
    final days = controller.days;

    return SizedBox(
      // The pill holds two stacked labels at a fixed height, so the height has
      // to follow the text size the user chose or they overlap.
      height: MediaQuery.textScalerOf(context).scale(52) + 24,
      child: ListView.separated(
        controller: scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: padding),
        itemCount: days.length,
        separatorBuilder: (_, _) => const SizedBox(width: gap),
        itemBuilder: (context, i) {
          final day = days[i];
          final selected = day == controller.selected;
          final isToday = day == controller.today;
          // Null means "not fetched": a marker on every day would claim an
          // empty schedule for a fortnight nobody has looked at yet.
          final count = controller.countFor(day);

          return Semantics(
            button: true,
            selected: selected,
            label: DateFormat.yMMMMEEEEd(locale).format(day),
            // ExcludeSemantics below drops the InkWell's own tap action along
            // with its labels, which would leave the pill unusable by a screen
            // reader.
            onTap: () => controller.select(day),
            child: ExcludeSemantics(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: pillWidth,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: selected ? kAnilistBlue : AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isToday && !selected
                        ? kAnilistBlue.withValues(alpha: 0.55)
                        : Colors.transparent,
                    width: 1.4,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => controller.select(day),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat.E(locale).format(day).toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: selected
                                ? Colors.white.withValues(alpha: 0.85)
                                : AppColors.textHint,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${day.day}',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: selected
                                ? Colors.white
                                : AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: (count ?? 0) > 0
                                ? (selected
                                      ? Colors.white.withValues(alpha: 0.9)
                                      : kAnilistBlue)
                                : Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The selected date in full, plus what the day actually holds.
///
/// The strip only shows a weekday and a bare number, and the list below carries
/// times and nothing else, so past the first week there is otherwise nothing on
/// screen saying which day is being read.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.controller});

  final AiringCalendarController controller;

  @override
  Widget build(BuildContext context) {
    final locale = context.locale.toString();
    final day = controller.selected;
    final date = DateFormat.MMMEd(locale).format(day);
    final count = controller.countFor(day);
    final total = controller.totalFor(day);

    final label = count == null
        ? date
        : controller.mineOnly
        ? '$date  ·  ${'anilist.calendar_count_mine'.tr(namedArgs: {'mine': '$count', 'total': '$total'})}'
        : '$date  ·  ${'anilist.calendar_count'.tr(namedArgs: {'count': '$count'})}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.textHint,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

/// All / my list toggle. Only offered while connected, since it needs a list.
class _MineFilter extends StatelessWidget {
  const _MineFilter({required this.controller});

  final AiringCalendarController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Row(
        children: [
          _FilterPill(
            label: 'anilist.calendar_all'.tr(),
            selected: !controller.mineOnly,
            onTap: () => controller.setMineOnly(false),
          ),
          const SizedBox(width: 8),
          _FilterPill(
            label: 'anilist.calendar_mine'.tr(),
            selected: controller.mineOnly,
            onTap: () => controller.setMineOnly(true),
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? kAnilistBlue.withValues(alpha: 0.16)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? kAnilistBlue : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected ? kAnilistBlue : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// The line between what has already aired and what is still to come.
class _NowDivider extends StatelessWidget {
  const _NowDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Row(
        children: [
          Text(
            'anilist.calendar_now'.tr().toUpperCase(),
            style: const TextStyle(
              color: kAnilistBlue,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              color: kAnilistBlue.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 0),
      padding: const EdgeInsetsDirectional.fromSTEB(11, 8, 6, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.border, width: 0.6),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 16,
            color: AppColors.textHint,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: kAnilistBlue,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'anilist.retry'.tr(),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder rows in the shape of the real ones.
///
/// A spinner in the middle of a blank page reads as a navigation, which is
/// wrong for something that happens on every swipe between days — and the row
/// geometry here is fixed, which is exactly when a skeleton beats a spinner.
class _DaySkeleton extends StatelessWidget {
  const _DaySkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(4),
      ),
    );

    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(height: 9),
      itemBuilder: (context, i) => Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 66,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  bar(double.infinity, 11),
                  const SizedBox(height: 8),
                  bar(90, 9),
                ],
              ),
            ),
            const SizedBox(width: 10),
            bar(42, 24),
          ],
        ),
      ),
    );
  }
}

/// The clock gutter beside a day's entries.
///
/// A day is a sequence in time, and a column of cards each carrying its own
/// time pill did not say so — the reader had to compare numbers to work out the
/// order. A continuous line with the hour printed where it changes reads as one
/// descending timeline instead.
class _TimeRailRow extends StatelessWidget {
  const _TimeRailRow({
    required this.at,
    required this.showTime,
    required this.aired,
    required this.first,
    required this.last,
    required this.child,
  });

  final DateTime at;
  final bool showTime;
  final bool aired;
  final bool first;
  final bool last;
  final Widget child;

  static const double _railWidth = 52;
  static const double _dotAt = 22;

  @override
  Widget build(BuildContext context) {
    final colour = aired ? AppColors.textHint : kAnilistBlue;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _railWidth,
            child: Stack(
              children: [
                // Two segments rather than one line: the run has to stop at the
                // first and last entry, or it hangs off both ends of the day.
                Positioned(
                  left: _railWidth - 13,
                  top: 0,
                  height: _dotAt,
                  child: _Segment(visible: !first),
                ),
                Positioned(
                  left: _railWidth - 13,
                  top: _dotAt,
                  bottom: -9,
                  child: _Segment(visible: !last),
                ),
                Positioned(
                  left: _railWidth - 16,
                  top: _dotAt - 3,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colour,
                    ),
                  ),
                ),
                if (showTime)
                  Positioned(
                    left: 0,
                    right: 18,
                    top: _dotAt - 8,
                    child: Text(
                      DateFormat.Hm(context.locale.toString()).format(at),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: colour,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      color: visible
          ? AppColors.textHint.withValues(alpha: 0.28)
          : Colors.transparent,
    );
  }
}

class _AiringCard extends StatelessWidget {
  const _AiringCard({
    required this.row,
    required this.mine,
    required this.onTap,
  });

  final AiringDayRow row;
  final bool mine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final airing = row.airing;
    final media = airing.media;
    final aired = airing.hasAired;
    final episode = row.isRange
        ? 'anilist.calendar_episode_range'.tr(
            namedArgs: {'from': '${row.firstEpisode}', 'to': '${row.lastEpisode}'},
          )
        : 'anilist.calendar_episode'.tr(
            namedArgs: {'episode': '${airing.episode}'},
          );

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: mine
                  ? kAnilistBlue.withValues(alpha: 0.4)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              // Faded once it has gone out, so a glance down the day separates
              // what is still to come from what already aired.
              Opacity(
                opacity: aired ? 0.55 : 1,
                child: AnilistCover(url: media.coverImage, width: 44, radius: 8),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            media.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.25,
                              fontWeight: FontWeight.w700,
                              color: aired
                                  ? AppColors.textSecondary
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (mine) ...[
                          const SizedBox(width: 6),
                          const AnilistLogo(size: 15, radius: 4),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      episode,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textHint,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What can be done with a title that is not on the viewer's list.
///
/// Deliberately short: the calendar's job is to hand a discovery over to the
/// rest of the app, and finding sources for it is the reason to be here at all.
class _MediaActions extends StatelessWidget {
  const _MediaActions({required this.media, required this.onAdd});

  final AnilistMedia media;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final siteUrl = media.siteUrl;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
        // Scrolls rather than clips: a three-line title, a large text scale or
        // a landscape phone all put this past the height a sheet is given.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnilistCover(url: media.coverImage, width: 54),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      media.displayTitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(color: AppColors.divider, height: 1),
              _SheetAction(
                icon: Icons.travel_explore_rounded,
                label: 'anilist.find_in_sources'.tr(),
                subtitle: 'anilist.find_in_sources_hint'.tr(),
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/cross-search', extra: media.displayTitle);
                },
              ),
              if (onAdd != null)
                _SheetAction(
                  icon: Icons.bookmark_add_outlined,
                  label: 'anilist.calendar_add_planning'.tr(),
                  onTap: () {
                    Navigator.of(context).pop();
                    onAdd!();
                  },
                ),
              _SheetAction(
                icon: Icons.open_in_new_rounded,
                label: 'anilist.open_on_anilist'.tr(),
                onTap: siteUrl == null
                    ? null
                    : () => launchUrl(
                        Uri.parse(siteUrl),
                        mode: LaunchMode.externalApplication,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: enabled,
      leading: Icon(
        icon,
        color: enabled ? kAnilistBlue : AppColors.textHint,
        size: 22,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: enabled ? AppColors.textPrimary : AppColors.textHint,
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(color: AppColors.textHint, fontSize: 12),
            ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.textHint,
        size: 20,
      ),
      onTap: onTap,
    );
  }
}
