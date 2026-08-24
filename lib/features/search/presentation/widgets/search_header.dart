import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/tv/tv.dart';

class SearchStickyHeader extends StatelessWidget {
  const SearchStickyHeader({
    super.key,
    required this.progress,
    required this.topPad,
    required this.controller,
    required this.focus,
    required this.hasActiveFilter,
    required this.showFilter,
    required this.onFilterTap,
    required this.onMultiSearchTap,
    required this.onQueryChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final double progress;
  final double topPad;
  final TextEditingController controller;
  final FocusNode focus;
  final bool hasActiveFilter;

  /// Hidden when the current provider exposes no genres — an empty filter
  /// sheet is worse than no button.
  final bool showFilter;
  final VoidCallback onFilterTap;
  final VoidCallback onMultiSearchTap;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final compactProgress = Curves.easeOutCubic.transform(
      progress.clamp(0.0, 1.0),
    );
    final topSpacing = lerpDouble(topPad + 18, topPad + 10, compactProgress)!;
    final titleHeight = lerpDouble(28, 0, compactProgress)!;
    final titleGap = lerpDouble(14, 8, compactProgress)!;
    final bottomGap = lerpDouble(16, 10, compactProgress)!;
    final blurred = progress > 0.01;
    final backgroundColor = blurred
        ? AppColors.background.withValues(alpha: 0.82)
        : AppColors.background;

    final inner = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: topSpacing),
        ClipRect(
          child: SizedBox(
            height: titleHeight,
            child: Opacity(
              opacity: 1 - compactProgress,
              child: Transform.translate(
                offset: Offset(0, -10 * compactProgress),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'search.title'.tr(),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: titleGap),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, bottomGap),
          child: Row(
            children: [
              Expanded(
                child: _SearchField(
                  controller: controller,
                  focus: focus,
                  onChanged: onQueryChanged,
                  onSubmitted: onSubmitted,
                  onClear: onClear,
                ),
              ),
              const SizedBox(width: 10),
              _HeaderIconButton(
                icon: Icons.travel_explore_rounded,
                onTap: onMultiSearchTap,
                tooltip: 'search.all_source_search'.tr(),
              ),
              if (showFilter) ...[
                const SizedBox(width: 10),
                _FilterButton(active: hasActiveFilter, onTap: onFilterTap),
              ],
            ],
          ),
        ),
      ],
    );

    final surface = Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.06 * progress),
          ),
        ),
      ),
      child: inner,
    );

    // An unscrolled page needs no save layer: a BackdropFilter at sigma 0 still
    // allocates one, on the same frames as the debounce and the poster decode.
    if (!blurred) return surface;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20 * progress, sigmaY: 20 * progress),
        child: surface,
      ),
    );
  }
}

/// Only the pieces that actually change rebuild on a keystroke: the clear icon
/// listens to the controller, the border listens to the focus node, and the
/// [TextField] itself is passed through untouched.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focus,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      focusNode: focus,
      cursorRadius: const Radius.circular(14),
      textInputAction: TextInputAction.search,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 15,
        height: 1,
      ),
      decoration: InputDecoration(
        hintText: 'search.hint'.tr(),
        hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 15),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppColors.textHint,
          size: 20,
        ),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            const icon = Icon(
              Icons.close_rounded,
              color: AppColors.textHint,
              size: 18,
            );
            // Android TV: the clear (X) is the only way to drop a query
            // without a hardware keyboard, so it needs to be a focus stop.
            if (isTvPlatform) {
              return TvFocusable(
                onPressed: onClear,
                borderRadius: 9,
                child: icon,
              );
            }
            return GestureDetector(onTap: onClear, child: icon);
          },
        ),
        border: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        isDense: true,
      ),
      onChanged: onChanged,
      onSubmitted: (value) {
        focus.unfocus();
        onSubmitted(value);
      },
      onTapOutside: (_) => focus.unfocus(),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ListenableBuilder(
        listenable: focus,
        child: field,
        builder: (context, child) {
          final focused = focus.hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            height: 46,
            // Focus reads as lit, not as outlined. A saturated red rectangle
            // around a text field is louder than anything else on the screen
            // and fights the dark surface it sits on; the brand colour carries
            // in a soft glow instead, where it says the same thing quietly.
            decoration: BoxDecoration(
              color: focused
                  ? AppColors.surfaceVariant.withValues(alpha: 0.96)
                  : AppColors.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: focused ? 0.16 : 0.08),
              ),
              boxShadow: focused
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.22),
                        blurRadius: 14,
                        spreadRadius: -2,
                      ),
                    ]
                  : null,
            ),
            child: child,
          );
        },
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      height: 46,
      width: 46,
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Icon(icon, size: 20, color: AppColors.textSecondary),
    );
    // Android TV: the search header's action buttons were unreachable by the
    // D-pad. Off TV this is the GestureDetector that was always here.
    final button = isTvPlatform
        ? TvFocusable(onPressed: onTap, borderRadius: 14, child: content)
        : GestureDetector(onTap: onTap, child: content);
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.onTap, required this.active});

  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      height: 46,
      width: 46,
      decoration: BoxDecoration(
        color: active
            ? AppColors.primary.withValues(alpha: 0.18)
            : AppColors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active
              ? AppColors.primary.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.tune_rounded,
            size: 20,
            color: active ? AppColors.primary : AppColors.textSecondary,
          ),
          if (active)
            Positioned(
              top: 9,
              right: 9,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );

    // Android TV: without this, the filter sheet could not be opened at all.
    if (isTvPlatform) {
      return TvFocusable(onPressed: onTap, borderRadius: 14, child: content);
    }

    return GestureDetector(onTap: onTap, child: content);
  }
}
