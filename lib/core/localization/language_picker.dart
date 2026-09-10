import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/localization/app_language.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';

/// The language control on the sign-in screen.
///
/// ## Why it is here and not on a screen of its own
///
/// The app already picks the right language by itself: with no saved choice,
/// `easy_localization` resolves the device locale, so a German phone opens in
/// German the moment `de.json` exists. A dedicated first-run language screen
/// would therefore charge every user a step to serve the minority whose phone
/// is set to something they do not want to read.
///
/// A chip costs nobody a step, and the slides re-render in the chosen language
/// straight away — which a picker placed *after* the introduction cannot do,
/// because by then the introduction has already been read in the wrong one.
class LanguageChip extends StatelessWidget {
  const LanguageChip({super.key});

  @override
  Widget build(BuildContext context) {
    final code = context.locale.languageCode;
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: () => showLanguageSheet(context),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.language_rounded,
                size: 18,
                color: AppColors.textPrimary,
              ),
              const SizedBox(width: 6),
              // The code, not the native name: "Bahasa Indonesia" is four times
              // the width of "EN" and the chip sits next to Skip in a row that
              // has no room to grow.
              Text(
                code.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    return Scaffold(
      appBar: AppBar(title: Text('profile.language'.tr())),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'ux.interface_language_note'.tr(),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  for (final locale in context.supportedLocales)
                    _LanguageRow(
                      code: locale.languageCode,
                      selected: selected == locale.languageCode,
                      onTap: () =>
                          setState(() => _selected = locale.languageCode),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: () => Navigator.pop(context, selected),
                child: Text('ux.continue'.tr()),
              ),
            ),
          ],
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
