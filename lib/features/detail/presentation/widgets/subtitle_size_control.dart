import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/entities/subtitle_style.dart';

/// Caption size as a stepper, a slider and four presets.
///
/// One widget for the player's subtitle sheet, its style editor and the
/// settings page, so the three cannot drift into different ranges — the
/// settings dropdown only knew sizes up to 32 and showed nothing selected for
/// a size picked in the player.
class SubtitleSizeControl extends StatelessWidget {
  const SubtitleSizeControl({
    super.key,
    required this.fontSize,
    required this.onChanged,
    this.showSlider = true,
  });

  final double fontSize;
  final ValueChanged<double> onChanged;

  /// Off on TV, where a slider is a trap for the D-pad and the stepper
  /// already covers the range.
  final bool showSlider;

  @override
  Widget build(BuildContext context) {
    final size = fontSize.clamp(
      SubtitleStyle.minFontSize,
      SubtitleStyle.maxFontSize,
    );
    final preset = SubtitleSizePreset.of(size);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _StepButton(
              icon: Icons.remove_rounded,
              onTap: size > SubtitleStyle.minFontSize
                  ? () => onChanged(SubtitleStyle.stepFontSize(size, -2))
                  : null,
            ),
            SizedBox(
              width: 44,
              child: Text(
                '${size.round()}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _StepButton(
              icon: Icons.add_rounded,
              onTap: size < SubtitleStyle.maxFontSize
                  ? () => onChanged(SubtitleStyle.stepFontSize(size, 2))
                  : null,
            ),
            if (showSlider)
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppColors.primary,
                    inactiveTrackColor: Colors.white12,
                    thumbColor: AppColors.primary,
                    overlayColor: AppColors.primary.withValues(alpha: 0.15),
                    trackHeight: 3,
                  ),
                  child: Slider(
                    min: SubtitleStyle.minFontSize,
                    max: SubtitleStyle.maxFontSize,
                    divisions:
                        (SubtitleStyle.maxFontSize - SubtitleStyle.minFontSize)
                            .round(),
                    value: size.roundToDouble(),
                    label: '${size.round()}',
                    onChanged: onChanged,
                  ),
                ),
              )
            else
              const Spacer(),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final p in SubtitleSizePreset.values) ...[
              Expanded(
                child: _PresetChip(
                  label: p.labelKey.tr(),
                  selected: p == preset,
                  onTap: () => onChanged(p.fontSize),
                ),
              ),
              if (p != SubtitleSizePreset.values.last) const SizedBox(width: 6),
            ],
          ],
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white10,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            icon,
            size: 20,
            color: onTap == null ? Colors.white24 : Colors.white,
          ),
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
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
          ? AppColors.primary.withValues(alpha: 0.18)
          : Colors.white10,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.primary : Colors.white12,
              width: selected ? 1.5 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
