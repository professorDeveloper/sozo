import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/localization/app_language.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';

/// First-run choice, after the introduction and before entering the app/auth.
Future<bool> confirmIntroLanguage(BuildContext context) async {
  final code = await Navigator.of(
    context,
  ).push<String>(MaterialPageRoute(builder: (_) => const IntroLanguagePage()));
  if (code == null || !context.mounted) return false;
  await AppLanguage.set(context, code);
  return true;
}

class IntroLanguagePage extends StatefulWidget {
  const IntroLanguagePage({super.key});

  @override
  State<IntroLanguagePage> createState() => _IntroLanguagePageState();
}

class _IntroLanguagePageState extends State<IntroLanguagePage> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final selected = _selected ?? context.locale.languageCode;
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const Spacer(),
                    Text(
                      'SOZO',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.2,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  itemCount: context.supportedLocales.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          8,
                          8,
                          8,
                          16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'profile.language'.tr(),
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'ux.interface_language_note'.tr(),
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    final locale = context.supportedLocales[index - 1];
                    return _LanguageRow(
                      code: locale.languageCode,
                      selected: selected == locale.languageCode,
                      onTap: () =>
                          setState(() => _selected = locale.languageCode),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, selected),
                  child: Text('ux.continue'.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lists every language the app ships, in its own name.
Future<void> showLanguageSheet(BuildContext context) {
  return showAdaptiveModal<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 20, 12),
            child: Text(
              'profile.language'.tr(),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // Scrolls rather than sizing to eleven rows: on a short phone in
          // landscape the full list is taller than the sheet is allowed to be.
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                for (final locale in context.supportedLocales)
                  _LanguageRow(
                    code: locale.languageCode,
                    selected:
                        locale.languageCode == context.locale.languageCode,
                    // The sheet's own context is popped; the change is applied
                    // through the page's, which outlives it.
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await AppLanguage.set(context, locale.languageCode);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.code,
    required this.selected,
    required this.onTap,
  });

  final String code;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      minTileHeight: 56,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      tileColor: selected
          ? AppColors.primary.withValues(alpha: 0.10)
          : Colors.transparent,
      leading: Text(
        AppLanguage.flagOf(code),
        semanticsLabel: AppLanguage.labelOf(code),
        style: const TextStyle(fontSize: 26),
      ),
      title: Text(
        AppLanguage.labelOf(code),
        style: TextStyle(
          color: selected ? AppColors.primary : AppColors.textPrimary,
          fontSize: 15,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      trailing: selected
          ? Icon(Icons.check_rounded, color: AppColors.primary, size: 20)
          : null,
    );
  }
}
