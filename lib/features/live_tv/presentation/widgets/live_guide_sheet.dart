import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/live_tv/data/live_tv_service.dart';

/// The programme guide, from inside the player.
///
/// Live TV had a guide all along, but only on the channel list — once you were
/// watching, the one screen where "what is this, and what is next" is the
/// actual question had no answer. You had to leave the stream to find out what
/// you were looking at.
///
/// Built as a sheet rather than as a side panel on purpose: every other list in
/// the player (speed, subtitles, servers, settings) arrives from the bottom,
/// and the side panel carries drawer/TV-focus machinery this does not need.
class LiveGuideSheet extends StatefulWidget {
  const LiveGuideSheet({
    super.key,
    required this.channelId,
    required this.channelName,
  });

  final String channelId;
  final String channelName;

  static Future<void> show(
    BuildContext context, {
    required String channelId,
    required String channelName,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      // Black, not the app surface: this opens over video, and a lighter sheet
      // reads as a different app.
      backgroundColor: const Color(0xF00A0A0A),
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => LiveGuideSheet(
        channelId: channelId,
        channelName: channelName,
      ),
    );
  }

  @override
  State<LiveGuideSheet> createState() => _LiveGuideSheetState();
}

class _LiveGuideSheetState extends State<LiveGuideSheet> {
  LiveSchedule? _schedule;
  bool _loading = true;
  Object? _error;

  /// Redraws the "now" block so its progress bar and remaining time stay true
  /// while the sheet is open. Thirty seconds is under a pixel of drift on the
  /// bar and costs nothing.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(
      const Duration(seconds: 30),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final schedule = await getIt<LiveTvService>().schedule(widget.channelId);
      if (!mounted) return;
      setState(() {
        _schedule = schedule;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.72;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
            child: Row(
              children: [
                const _LiveDot(),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.channelName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Flexible(child: _body()),
          SizedBox(height: MediaQuery.paddingOf(context).bottom + 10),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
        ),
      );
    }

    final schedule = _schedule;
    if (_error != null || schedule == null || schedule.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        // A channel with no guide is ordinary — most free feeds carry none —
        // so this says so plainly rather than looking like a failure.
        child: Text(
          'live_tv.no_guide'.tr(),
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      );
    }

    final now = DateTime.now();
    final current = schedule.currentAt(now);
    final upcoming = schedule
        .from(now)
        .where((p) => p.start != null && !p.isLiveAt(now))
        .toList(growable: false);

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      children: [
        if (current != null) _nowBlock(current, now),
        if (upcoming.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'live_tv.up_next'.tr(),
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < upcoming.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
            _row(upcoming[i]),
          ],
        ],
      ],
    );
  }

  Widget _nowBlock(LiveProgramme programme, DateTime now) {
    final progress = programme.progressAt(now);
    final stop = programme.stop;
    final left = stop?.difference(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          programme.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
        if (programme.subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            programme.subtitle,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
        ],
        if (programme.hasWindow) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: Colors.white.withValues(alpha: 0.14),
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '${_hhmm(programme.start!)} – ${_hhmm(stop!)}',
                style: TextStyle(color: AppColors.textHint, fontSize: 11.5),
              ),
              const Spacer(),
              if (left != null && !left.isNegative)
                Text(
                  'live_tv.minutes_left'.tr(args: ['${left.inMinutes}']),
                  style: TextStyle(color: AppColors.textHint, fontSize: 11.5),
                ),
            ],
          ),
        ],
        if (programme.description.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            programme.description,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  Widget _row(LiveProgramme programme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 46,
            child: Text(
              _hhmm(programme.start!),
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  programme.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (programme.subtitle.isNotEmpty)
                  Text(
                    programme.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textHint,
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) => Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: Color(0xFFE53935),
          shape: BoxShape.circle,
        ),
      );
}
