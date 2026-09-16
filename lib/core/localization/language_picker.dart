import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/localization/app_language.dart';
import 'package:soplay/core/theme/app_colors.dart';

/// First-run choice, after the introduction and before entering the app/auth.
Future<bool> confirmIntroLanguage(BuildContext context) async {
  final code = await Navigator.of(
    context,
  ).push<String>(MaterialPageRoute(builder: (_) => const LanguagePage()));
  if (code == null || !context.mounted) return false;
  await AppLanguage.set(context, code);
  return true;
}

/// The same page from Settings, where picking one applies it.
Future<void> openLanguagePage(BuildContext context) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const LanguagePage(firstRun: false),
      ),
    );

/// Every language the app ships, in its own name.
///
/// One page for both places it is asked. First run is a step in a sequence, so
/// it confirms and hands the answer back; Settings is a setting, so a tap is the
/// change and the page closes behind it — which is what every other row in
/// Settings does.
///
/// It had three implementations: this page, a bottom sheet nothing called, and
/// a dropdown in Settings. Three ways to make one choice is three places for it
/// to drift, and the dropdown was the one people actually met.
class LanguagePage extends StatefulWidget {
  const LanguagePage({super.key, this.firstRun = true});

  /// Show the wordmark and a Continue button, rather than applying on tap.
  final bool firstRun;

  @override
  State<LanguagePage> createState() => _LanguagePageState();
}

class _LanguagePageState extends State<LanguagePage> {
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
                    if (widget.firstRun)
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
                      onTap: () async {
                        if (widget.firstRun) {
                          setState(() => _selected = locale.languageCode);
                          return;
                        }
                        // Applied through the page's own context, which
                        // outlives this one being popped.
                        final navigator = Navigator.of(context);
                        await AppLanguage.set(context, locale.languageCode);
                        navigator.pop();
                      },
                    );
                  },
                ),
              ),
              if (widget.firstRun)
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
