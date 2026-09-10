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
    this.onTorrentTap,
    required this.onQueryChanged,
    required this.onSubmitted,
    required this.onClear,
    this.voiceButton,
  });

  /// Shown inside the field while it is empty, where the clear button sits once
  /// there is something to clear. Null on the platforms with no recogniser.
  final Widget? voiceButton;

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

  /// Jumps to the torrent search with whatever is typed. Null where torrents
  /// are unavailable (iOS, desktop), so the action is absent rather than
  /// present and failing.
  final VoidCallback? onTorrentTap;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final blurred = progress > 0.01;
    final backgroundColor = blurred
        ? AppColors.background.withValues(alpha: 0.95)
        : AppColors.background;
    final inner = Padding(
      padding: EdgeInsets.fromLTRB(16, topPad + 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'search.title'.tr(),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          _SearchField(
            controller: controller,
            focus: focus,
            onChanged: onQueryChanged,
            onSubmitted: onSubmitted,
            onClear: onClear,
            voiceButton: voiceButton,
          ),
          const SizedBox(height: 8),
          // Actions never steal width from the query or appear mid-keystroke.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _SearchAction(
                  icon: Icons.travel_explore_rounded,
                  label: 'search.all_source_search'.tr(),
                  onTap: onMultiSearchTap,
                ),
                if (onTorrentTap != null) ...[
                  const SizedBox(width: 8),
                  _SearchAction(
                    icon: Icons.hub_rounded,
                    label: 'ux.torrents'.tr(),
                    onTap: onTorrentTap!,
                  ),
                ],
                if (showFilter) ...[
                  const SizedBox(width: 8),
                  _SearchAction(
                    icon: Icons.tune_rounded,
                    label: 'ux.filters'.tr(),
                    onTap: onFilterTap,
                    selected: hasActiveFilter,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
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
    this.voiceButton,
  });

  final Widget? voiceButton;

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
            // Microphone while there is nothing to clear, clear button once
            // there is. They never both apply, so the two share one slot rather
            // than crowding the field with a second icon.
            if (value.text.isEmpty) {
              return voiceButton ?? const SizedBox.shrink();
            }
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
            return IconButton(
              tooltip: 'general.clear'.tr(),
              onPressed: onClear,
              icon: icon,
            );
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
            constraints: BoxConstraints(
              minHeight: 52 + (MediaQuery.textScalerOf(context).scale(15) - 15),
            ),
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

class _SearchAction extends StatelessWidget {
  const _SearchAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: selected
            ? AppColors.primaryLight
            : AppColors.textSecondary,
        backgroundColor: selected
            ? AppColors.primary.withValues(alpha: 0.14)
            : AppColors.surface,
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    ),
  );
}
