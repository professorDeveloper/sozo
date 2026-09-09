import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';

/// The "nothing in this tab" panel, at one geometry for every tab that has one.
///
/// Four hand-written copies had drifted apart: Similar and Cast at 56pt of
/// vertical padding, Screenshots at 40, and Relations with no icon at all and
/// its message two points smaller in a dimmer grey. A title with thin metadata
/// is empty in three or four tabs at once, so swiping across it walked through
/// several different-looking blank screens — which reads as several different
/// failures rather than one absence.
///
/// The kept geometry is the icon-bearing one. Every one of these lands in a tab
/// pane the detail page stretches to nearly the full window height, and at that
/// size a lone 13pt line is a speck the eye has to hunt for; the icon is what
/// says where to look before anything is read. What Relations contributed is
/// the wrapping — centred, 1.45 line height, 24pt side gutters — because its
/// message is the one long enough to wrap, and the short ones are unharmed by
/// room they never use.
class DetailEmptyState extends StatelessWidget {
  const DetailEmptyState({
    super.key,
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.textHint, size: 48),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
