import 'package:flutter/material.dart';
import 'package:soplay/core/theme/kaizoku_colors.dart';
import 'package:soplay/features/streak/domain/entities/streak_state.dart';

const Color _ember = KaizokuColors.solarAmber;
const Color _emberDeep = KaizokuColors.neonCrimson;

/// A 5×7 (35-cell) activity heatmap built from [StreakState.calendar]
/// (oldest → newest, newest anchored to the bottom-right cell).
class StreakCalendarHeatmap extends StatelessWidget {
  const StreakCalendarHeatmap({super.key, required this.days});

  final List<StreakDay> days;

  static const int _cols = 7;
  static const int _rows = 5;
  static const int _total = _cols * _rows;

  @override
  Widget build(BuildContext context) {
    final cells = List<StreakDay?>.filled(_total, null, growable: false);
    final offset = (_total - days.length).clamp(0, _total);
    for (var i = 0; i < days.length; i++) {
      final idx = offset + i;
      if (idx >= 0 && idx < _total) cells[idx] = days[i];
    }
    final todayIdx = days.isEmpty ? -1 : (offset + days.length - 1);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KaizokuColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: KaizokuColors.cardBorder,
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          for (var r = 0; r < _rows; r++) ...[
            Row(
              children: [
                for (var c = 0; c < _cols; c++) ...[
                  Expanded(
                    child: _HeatCell(
                      day: cells[r * _cols + c],
                      isToday: r * _cols + c == todayIdx,
                    ),
                  ),
                  if (c < _cols - 1) const SizedBox(width: 6),
                ],
              ],
            ),
            if (r < _rows - 1) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _HeatCell extends StatelessWidget {
  const _HeatCell({required this.day, required this.isToday});

  final StreakDay? day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final active = day?.active ?? false;
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: active
              ? _ember.withValues(alpha: 0.8)
              : (day == null
                  ? Colors.white.withValues(alpha: 0.015)
                  : Colors.white.withValues(alpha: 0.05)),
          border: isToday
              ? Border.all(color: _emberDeep, width: 1.5)
              : null,
        ),
      ),
    );
  }
}
