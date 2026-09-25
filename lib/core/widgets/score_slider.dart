import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A score on a ten-point scale, given with a slider that reads it out.
///
/// Shared by the places a score is chosen — a tracker entry, a filter's
/// minimum — so a rating looks and behaves the same wherever it is set. The
/// colour runs red to green the way critics' scores are drawn, the number
/// follows the thumb, and [describe] says in words what it amounts to.
///
/// [onChanged] fires as the thumb moves, for the display; [onChangeEnd] once
/// it is let go, which is where anything expensive — a network write —
/// belongs. A score written on every step of a drag was ten requests for one
/// decision, and the controls froze while they went out.
class ScoreSlider extends StatelessWidget {
  const ScoreSlider({
    super.key,
    required this.value,
    required this.onChanged,
    required this.describe,
    this.onChangeEnd,
    this.max = 10,
    this.enabled = true,
    this.note,
    this.suffix = '',
  });

  /// 0 is "none"; otherwise the score out of [max].
  final int value;
  final int max;
  final ValueChanged<int> onChanged;
  final ValueChanged<int>? onChangeEnd;

  /// Words for a value, 0 included.
  final String Function(int value) describe;
  final bool enabled;
  final String? note;

  /// After the number: "+" for a minimum, nothing for a score.
  final String suffix;

  static Color colorFor(int v, ColorScheme scheme) {
    if (v == 0) return scheme.outline;
    if (v < 5) return const Color(0xFFE5533D);
    if (v < 6) return const Color(0xFFF08A24);
    if (v < 7) return const Color(0xFFF5C518);
    if (v < 8) return const Color(0xFF9CCC4A);
    return const Color(0xFF3FB950);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = colorFor(value, theme.colorScheme);
    final muted = !enabled;
    return Opacity(
      opacity: muted ? 0.5 : 1,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: value == 0 ? 0.12 : 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_rounded, size: 18, color: color),
                      const SizedBox(width: 4),
                      Text(
                        value == 0 ? '—' : '$value$suffix',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: value == 0 ? theme.colorScheme.outline : color,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    describe(value),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6,
                activeTrackColor: color,
                inactiveTrackColor: theme.colorScheme.surfaceContainerHighest,
                thumbColor: color,
                overlayColor: color.withValues(alpha: 0.14),
                activeTickMarkColor: Colors.white.withValues(alpha: 0.5),
                inactiveTickMarkColor: theme.colorScheme.outlineVariant,
                valueIndicatorColor: color,
                showValueIndicator: ShowValueIndicator.onDrag,
              ),
              child: Slider(
                value: value.clamp(0, max).toDouble(),
                max: max.toDouble(),
                divisions: max,
                label: value == 0 ? describe(0) : '★ $value$suffix',
                semanticFormatterCallback: (v) => describe(v.round()),
                onChanged: enabled
                    ? (v) {
                        if (v.round() == value) return;
                        HapticFeedback.selectionClick();
                        onChanged(v.round());
                      }
                    : null,
                onChangeEnd: enabled && onChangeEnd != null
                    ? (v) => onChangeEnd!(v.round())
                    : null,
              ),
            ),
            Padding(
              // One label per stop, inset by the slider's own padding so
              // each sits under the position it names.
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var tick = 0; tick <= max; tick++)
                    Text(
                      tick == 0 ? '·' : '$tick',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (note != null) ...[
              const SizedBox(height: 6),
              Text(note!, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
