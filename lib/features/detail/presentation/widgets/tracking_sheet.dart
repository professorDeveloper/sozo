import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/system/responsive.dart';

/// One tracker's row on the viewer's list, as the sheet sees it.
class TrackerEntry {
  const TrackerEntry({
    required this.status,
    required this.progress,
    this.total,
    this.score,
  });

  /// The tracker's own status value, null when the title is not listed.
  final String? status;
  final int progress;
  final int? total;

  /// Out of 10; null or 0 when unscored.
  final int? score;

  bool get onList => status != null;

  TrackerEntry copyWith({String? status, int? progress, int? score}) =>
      TrackerEntry(
        status: status ?? this.status,
        progress: progress ?? this.progress,
        total: total,
        score: score ?? this.score,
      );
}

/// A status a tracker knows, with its label.
class TrackerStatus {
  const TrackerStatus(this.value, this.label);
  final String value;
  final String label;
}

/// What the sheet needs from a tracker, so AniList and MyAnimeList share
/// one sheet: read the row, write a change, take the row off the list.
abstract class TrackerEditor {
  String get name;
  Widget get logo;
  Color get accent;

  /// What to say when a write fails.
  String get saveFailed;

  /// Chapters rather than episodes on the progress row.
  bool get isManga;
  List<TrackerStatus> get statuses;

  Future<TrackerEntry?> load();
  Future<TrackerEntry> save(
    TrackerEntry current, {
    String? status,
    int? progress,
    int? score,
  });
  Future<void> remove(TrackerEntry current);
}

/// Where a title is on the viewer's list, and every way to move it.
///
/// The row on the page shows the status and the number and moves the number
/// by one. This is the rest: the status itself, a score, a bigger jump, and
/// the way off the list. Every tap writes straight away — a sheet with a Save
/// button is a sheet whose changes are lost when it is swiped off — and a
/// failed write puts the value back and says so.
class TrackingSheet extends StatefulWidget {
  const TrackingSheet({
    super.key,
    required this.editor,
    required this.title,
    required this.entry,
  });

  final TrackerEditor editor;
  final String title;
  final TrackerEntry entry;

  /// Resolves when the sheet closes. Every tap in it wrote straight away,
  /// so the row behind reloads whatever happened.
  static Future<void> show(
    BuildContext context, {
    required TrackerEditor editor,
    required String title,
    required TrackerEntry entry,
  }) async {
    await showAdaptiveModal<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => TrackingSheet(editor: editor, title: title, entry: entry),
    );
  }

  @override
  State<TrackingSheet> createState() => _TrackingSheetState();
}

class _TrackingSheetState extends State<TrackingSheet> {
  late TrackerEntry _entry = widget.entry;
  bool _busy = false;

  TrackerEditor get _e => widget.editor;

  Future<void> _write({String? status, int? progress, int? score}) async {
    if (_busy) return;
    final before = _entry;
    // Painted first; the request confirms or reverts it.
    setState(() {
      _busy = true;
      _entry = before.copyWith(
        status: status,
        progress: progress,
        score: score,
      );
    });
    HapticFeedback.selectionClick();
    try {
      final saved = await _e.save(
        before,
        status: status,
        progress: progress,
        score: score,
      );
      if (!mounted) return;
      setState(() => _entry = saved);
    } catch (_) {
      if (!mounted) return;
      setState(() => _entry = before);
      _say(_e.saveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _e.remove(_entry);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _say(_e.saveFailed);
    }
  }

  void _say(String text) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final e = _entry;
    final total = e.total;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          10,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _e.logo,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _e.name,
                        style: TextStyle(
                          color: _e.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                      Text(
                        widget.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _Label('detail.tracking_status'.tr()),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final st in _e.statuses)
                  _Pill(
                    label: st.label,
                    accent: _e.accent,
                    selected: e.status == st.value,
                    onTap: e.status == st.value
                        ? null
                        : () => _write(status: st.value),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _Label(
              _e.isManga
                  ? 'detail.tracking_chapters_read'.tr()
                  : 'detail.tracking_episodes_watched'.tr(),
            ),
            const SizedBox(height: 8),
            _Stepper(
              value: e.progress,
              text: total != null ? '${e.progress} / $total' : '${e.progress}',
              accent: _e.accent,
              onLess: e.onList && e.progress > 0
                  ? () => _write(progress: e.progress - 1)
                  : null,
              onMore: e.onList && (total == null || e.progress < total)
                  ? () => _write(progress: e.progress + 1)
                  : null,
              // A long press jumps: to the end, which is the common case
              // for something already watched, or back to the start.
              onMoreLong: e.onList && total != null && e.progress < total
                  ? () => _write(progress: total)
                  : null,
              onLessLong: e.onList && e.progress > 0
                  ? () => _write(progress: 0)
                  : null,
            ),
            const SizedBox(height: 20),
            _Label('detail.tracking_score'.tr()),
            const SizedBox(height: 8),
            _ScoreBar(
              score: e.score ?? 0,
              accent: _e.accent,
              enabled: e.onList && !_busy,
              onScore: (v) => _write(score: v),
            ),
            const SizedBox(height: 24),
            if (e.onList)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _busy ? null : _remove,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFE5484D),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  label: Text('detail.tracking_remove'.tr()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      color: AppColors.textSecondary,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.1,
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color accent;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? accent : Colors.white.withValues(alpha: 0.06),
    borderRadius: BorderRadius.circular(999),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textPrimary,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    ),
  );
}

/// − value + on one line, with long-press jumps where they make sense.
/// A score, scored the way a score is given: by pointing at it.
///
/// This was the same −/+ [_Stepper] as the episode counter directly above it,
/// reading "Not scored" or "★ 7 / 10". Two problems. Mechanically, putting 8/10
/// on a title took eight taps. And visually the two rows were identical, so the
/// thing that counts episodes and the thing that rates the show looked like one
/// control repeated — nothing about it said "this is a rating".
///
/// Ten stars, tapped directly. Tapping the star you are already on clears the
/// score, which is the only way back to "not scored" and is what every app that
/// does this supports.
class _ScoreBar extends StatelessWidget {
  const _ScoreBar({
    required this.score,
    required this.accent,
    required this.enabled,
    required this.onScore,
  });

  final int score;
  final Color accent;
  final bool enabled;
  final ValueChanged<int> onScore;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      slider: true,
      enabled: enabled,
      value: score == 0 ? 'detail.tracking_not_scored'.tr() : '$score / 10',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 1; i <= 10; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    label: '$i / 10',
                    excludeSemantics: true,
                    child: InkResponse(
                      // Tapping the current score again means "take it off".
                      onTap: enabled ? () => onScore(i == score ? 0 : i) : null,
                      radius: 20,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Icon(
                          i <= score
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 26,
                          color: i <= score
                              ? accent
                              : Colors.white.withValues(
                                  alpha: enabled ? 0.28 : 0.14,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            score == 0
                ? 'detail.tracking_not_scored'.tr()
                : '$score / 10',
            style: TextStyle(
              color: score == 0 ? AppColors.textHint : AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.text,
    required this.accent,
    required this.onLess,
    required this.onMore,
    this.onLessLong,
    this.onMoreLong,
  });

  final int value;
  final String text;
  final Color accent;
  final VoidCallback? onLess;
  final VoidCallback? onMore;
  final VoidCallback? onLessLong;
  final VoidCallback? onMoreLong;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        _Step(icon: Icons.remove_rounded, onTap: onLess, onLong: onLessLong),
        Expanded(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        _Step(icon: Icons.add_rounded, onTap: onMore, onLong: onMoreLong),
      ],
    ),
  );
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.onTap, this.onLong});

  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onLong;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    onLongPress: onLong,
    borderRadius: BorderRadius.circular(12),
    child: SizedBox(
      width: 52,
      height: 48,
      child: Icon(
        icon,
        size: 24,
        color: onTap == null
            ? AppColors.textHint.withValues(alpha: 0.4)
            : AppColors.textPrimary,
      ),
    ),
  );
}
