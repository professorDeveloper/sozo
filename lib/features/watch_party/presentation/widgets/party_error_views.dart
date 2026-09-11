import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_theme.dart';
import 'package:soplay/core/theme/kaizoku_colors.dart';

/// Full-screen glass card for a party terminal / error state. Mirrors the visual
/// idiom of `my_list_state_views.dart`.
class PartyStateView extends StatelessWidget {
  const PartyStateView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 60),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              decoration: BoxDecoration(
                color: KaizokuColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: KaizokuColors.cardBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          KaizokuColors.neonCrimson.withValues(alpha: 0.22),
                          KaizokuColors.neonCrimson.withValues(alpha: 0.06),
                        ],
                      ),
                      border: Border.all(
                        color: KaizokuColors.neonCrimson.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Icon(icon, color: KaizokuColors.neonCrimson, size: 30),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      message!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: KaizokuColors.textSecondary,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: 22),
                    SizedBox(
                      height: 46,
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: onAction,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: KaizokuColors.neonCrimson,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(kButtonRadius),
                          ),
                        ),
                        child: Text(actionLabel!),
                      ),
                    ),
                  ],
                  if (secondaryLabel != null && onSecondary != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: onSecondary,
                        child: Text(
                          secondaryLabel!,
                          style: const TextStyle(color: KaizokuColors.textSecondary),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Maps a `party:error` code to a full-screen state view.
class PartyErrorView extends StatelessWidget {
  const PartyErrorView({
    super.key,
    required this.code,
    this.actionLabel,
    this.onAction,
  });

  final String code;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final (icon, titleKey) = switch (code) {
      'not_found' || 'bad_code' => (
          Icons.search_off_rounded,
          'watch_party.error_not_found',
        ),
      'full' => (Icons.group_off_rounded, 'watch_party.error_full'),
      'forbidden' => (Icons.lock_outline_rounded, 'watch_party.error_forbidden'),
      'rate' => (Icons.timer_outlined, 'watch_party.error_rate'),
      'unauthorized' => (
          Icons.lock_person_rounded,
          'watch_party.error_unauthorized',
        ),
      _ => (Icons.error_outline_rounded, 'watch_party.error_generic'),
    };
    return PartyStateView(
      icon: icon,
      title: titleKey.tr(),
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}

/// Full-screen state for a closed room (`party:closed`).
class PartyClosedView extends StatelessWidget {
  const PartyClosedView({
    super.key,
    this.reason,
    this.actionLabel,
    this.onAction,
  });

  final String? reason;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return PartyStateView(
      icon: Icons.meeting_room_outlined,
      title: 'watch_party.room_closed'.tr(),
      message: reason == 'empty'
          ? 'watch_party.room_closed_empty'.tr()
          : null,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}
