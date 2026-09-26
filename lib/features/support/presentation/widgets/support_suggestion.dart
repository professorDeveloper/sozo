import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/support/data/support_models.dart';

/// "Keeps happening? Write to support" under an error.
///
/// Opens a request already on the right category, naming the screen, the
/// source and the error that was on it, so the viewer only has to say what
/// they were doing. Quiet on purpose: it sits under Retry, never instead of it.
class SupportSuggestion extends StatelessWidget {
  const SupportSuggestion({
    super.key,
    required this.screen,
    this.category = SupportCategory.bug,
    this.provider,
    this.content,
    this.error,
  });

  final String screen;
  final SupportCategory category;
  final String? provider;
  final String? content;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => context.push(
        '/support/new',
        extra: SupportRequestArgs(
          category: category,
          screen: screen,
          provider: provider,
          content: content,
          error: error,
        ),
      ),
      style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
      icon: const Icon(Icons.support_agent_rounded, size: 17),
      label: Text('support.suggest'.tr(), style: const TextStyle(fontSize: 13)),
    );
  }
}
