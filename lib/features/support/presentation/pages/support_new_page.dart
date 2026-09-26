import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/app_buttons.dart';
import 'package:soplay/features/profile/presentation/widgets/settings_tiles.dart';
import 'package:soplay/features/support/data/support_diagnostics.dart';
import 'package:soplay/features/support/data/support_models.dart';
import 'package:soplay/features/support/data/support_repository.dart';
import 'package:soplay/features/support/presentation/support_style.dart';

/// A new request to support.
///
/// Diagnostics are the viewer's choice — on by default, one switch to turn
/// off — and shown in full before anything is sent.
class SupportNewPage extends StatefulWidget {
  const SupportNewPage({super.key, this.args});

  final SupportRequestArgs? args;

  @override
  State<SupportNewPage> createState() => _SupportNewPageState();
}

class _SupportNewPageState extends State<SupportNewPage> {
  final SupportRepository _repo = getIt<SupportRepository>();
  final HiveService _hive = getIt<HiveService>();
  final TextEditingController _message = TextEditingController();
  final TextEditingController _contact = TextEditingController();

  late SupportCategory? _category = widget.args?.category;
  bool _attach = true;
  bool _showDiagnostics = false;
  bool _sending = false;
  String? _error;
  Map<String, String>? _diagnostics;
  Future<void>? _collecting;

  bool get _guest => !_hive.isLoggedIn;
  bool get _canSend =>
      !_sending && _category != null && _message.text.trim().length >= 3;

  @override
  void initState() {
    super.initState();
    _message.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Once: the locale it reads needs the context, which initState lacks.
    _collecting ??= _collect();
  }

  Future<void> _collect() async {
    final d = await SupportDiagnostics.collect(
      language: context.locale.languageCode,
      args: widget.args,
    );
    if (mounted) setState(() => _diagnostics = d);
  }

  @override
  void dispose() {
    _message.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_canSend) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
    });
    // Collected when the page opened; a send in the first instant waits for it.
    if (_attach) await _collecting;
    if (!mounted) return;
    try {
      final ticket = await _repo.create(
        category: _category!,
        message: _message.text.trim(),
        contact: _guest ? _contact.text : null,
        diagnostics: _attach ? _diagnostics : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('support.sent'.tr())));
      context.pushReplacement('/support/${ticket.id}');
    } on SupportException catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: 'support.new_request'.tr(),
      children: [
        SettingsLabel('support.category_title'.tr()),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in SupportCategory.values)
              ChoiceChip(
                avatar: Icon(
                  c.icon,
                  size: 18,
                  color: _category == c
                      ? AppColors.onPrimary
                      : AppColors.textSecondary,
                ),
                label: Text(c.label),
                selected: _category == c,
                showCheckmark: false,
                onSelected: _sending
                    ? null
                    : (_) => setState(() => _category = c),
                labelStyle: TextStyle(
                  color: _category == c
                      ? AppColors.onPrimary
                      : AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.surface,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
              ),
          ],
        ),
        const SizedBox(height: 20),
        SettingsLabel('support.message_label'.tr()),
        _Field(
          controller: _message,
          hint: 'support.message_hint'.tr(),
          minLines: 5,
          maxLines: 12,
          maxLength: 2000,
          enabled: !_sending,
        ),
        if (_guest) ...[
          const SizedBox(height: 16),
          SettingsLabel('support.contact_label'.tr()),
          _Field(
            controller: _contact,
            hint: 'support.contact_hint'.tr(),
            maxLength: 120,
            enabled: !_sending,
          ),
          const SizedBox(height: 6),
          Text(
            'support.contact_note'.tr(),
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 20),
        _DiagnosticsCard(
          attach: _attach,
          onAttach: _sending ? null : (v) => setState(() => _attach = v),
          expanded: _showDiagnostics,
          onToggle: () => setState(() => _showDiagnostics = !_showDiagnostics),
          diagnostics: _diagnostics ?? const {},
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(
            _error!,
            style: const TextStyle(color: AppColors.errorLight, fontSize: 13),
          ),
        ],
        const SizedBox(height: 20),
        AppPrimaryButton(
          label: 'support.send'.tr(),
          icon: Icons.send_rounded,
          loading: _sending,
          onPressed: _canSend ? _send : null,
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    this.minLines = 1,
    this.maxLines = 1,
    this.maxLength,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String hint;
  final int minLines;
  final int maxLines;
  final int? maxLength;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
      textCapitalization: TextCapitalization.sentences,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 14),
        filled: true,
        fillColor: AppColors.surface,
        counterStyle: const TextStyle(color: AppColors.textHint, fontSize: 11),
        contentPadding: const EdgeInsets.all(14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.primary, width: 1.2),
        ),
      ),
    );
  }
}

class _DiagnosticsCard extends StatelessWidget {
  const _DiagnosticsCard({
    required this.attach,
    required this.onAttach,
    required this.expanded,
    required this.onToggle,
    required this.diagnostics,
  });

  final bool attach;
  final ValueChanged<bool>? onAttach;
  final bool expanded;
  final VoidCallback onToggle;
  final Map<String, String> diagnostics;

  @override
  Widget build(BuildContext context) {
    final fields = diagnostics.entries.where((e) => e.key != 'log').toList();
    final log = diagnostics['log'];
    final logLines = log == null ? 0 : '\n'.allMatches(log).length;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            value: attach,
            onChanged: onAttach,
            activeTrackColor: AppColors.primary,
            contentPadding: const EdgeInsets.fromLTRB(14, 4, 8, 0),
            title: Text(
              'support.diag_title'.tr(),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'support.diag_body'.tr(),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ),
          ),
          if (attach)
            TextButton.icon(
              onPressed: onToggle,
              icon: Icon(
                expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 18,
              ),
              label: Text(
                expanded ? 'general.hide'.tr() : 'support.diag_show'.tr(),
              ),
            ),
          if (attach && expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final e in fields)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${e.key}: ',
                              style: const TextStyle(color: AppColors.textHint),
                            ),
                            TextSpan(
                              text: e.value,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        style: const TextStyle(fontSize: 12.5, height: 1.35),
                      ),
                    ),
                  if (log != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'support.diag_log_lines'.tr(args: ['$logLines']),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
