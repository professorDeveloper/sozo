import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/support/presentation/widgets/support_suggestion.dart';

class MyListEmptyView extends StatelessWidget {
  const MyListEmptyView({super.key});

  @override
  Widget build(BuildContext context) {
    return MyListStateView(
      icon: Icons.bookmark_border_rounded,
      title: 'my_list.empty_title'.tr(),
      message: 'my_list.empty_subtitle'.tr(),
    );
  }
}

class MyListUnauthorizedView extends StatelessWidget {
  const MyListUnauthorizedView({super.key, required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return MyListStateView(
      icon: Icons.lock_outline_rounded,
      title: 'my_list.unauth_title'.tr(),
      message: 'my_list.unauth_subtitle'.tr(),
      actionLabel: 'auth.sign_in'.tr(),
      onAction: onLogin,
    );
  }
}

class MyListErrorView extends StatelessWidget {
  const MyListErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MyListStateView(
      icon: Icons.wifi_off_rounded,
      title: 'my_list.error_title'.tr(),
      message: message,
      actionLabel: 'general.try_again'.tr(),
      onAction: onRetry,
      footer: SupportSuggestion(screen: 'my_list', error: message),
    );
  }
}

class MyListStateView extends StatelessWidget {
  const MyListStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Under the action, on an error only: the way to support.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _IconCircle(icon: icon),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: 22),
                    SizedBox(
                      height: 46,
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: onAction,
                        child: Text(actionLabel!),
                      ),
                    ),
                  ],
                  if (footer != null) ...[const SizedBox(height: 8), footer!],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconCircle extends StatelessWidget {
  const _IconCircle({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.22),
            AppColors.primary.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
      ),
      child: Icon(icon, color: AppColors.primaryLight, size: 30),
    );
  }
}
