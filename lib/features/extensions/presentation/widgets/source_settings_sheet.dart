import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/extensions/data/mangayomi_repo_store.dart';
import 'package:soplay/features/extensions/data/mangayomi_runtime.dart';
import 'package:soplay/features/extensions/domain/entities/mangayomi_source.dart';
import 'package:soplay/features/extensions/domain/source_preference.dart';

/// The settings a JavaScript source declares — a Mangayomi source's
/// preferences or an LNReader plugin's settings: its domain, the quality it
/// prefers, whether locked chapters are hidden. They were read by the source
/// and could not be changed from anywhere.
///
/// Saved as they change, to the same per-source store the source reads
/// before every call.
class SourceSettingsSheet extends StatefulWidget {
  const SourceSettingsSheet({super.key, required this.source});

  final MangayomiSource source;

  static Future<void> show(BuildContext context, MangayomiSource source) =>
      showAdaptiveModal<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => SourceSettingsSheet(source: source),
      );

  @override
  State<SourceSettingsSheet> createState() => _SourceSettingsSheetState();
}

class _SourceSettingsSheetState extends State<SourceSettingsSheet> {
  final MangayomiRepoStore _store = getIt<MangayomiRepoStore>();
  List<SourcePreference>? _prefs;
  late Map<String, dynamic> _saved = _store.prefs(widget.source.id);
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await getIt<MangayomiRuntime>().call(
        widget.source.id,
        'getSourcePreferences',
      );
      if (!mounted) return;
      setState(() {
        _prefs = [
          for (final p in (raw as List? ?? const []))
            ?SourcePreference.fromJson(p),
        ];
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _set(String key, Object? value) async {
    setState(() => _saved = {..._saved, key: value});
    await _store.savePrefs(widget.source.id, _saved);
  }

  Future<void> _reset() async {
    setState(() => _saved = {});
    await _store.savePrefs(widget.source.id, const {});
  }

  Future<void> _editText(TextSourcePreference p) async {
    final controller = TextEditingController(text: p.read(_saved));
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(p.title),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('general.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text('general.save'.tr()),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) await _set(p.key, value.trim());
  }

  Future<void> _pickOne(ListSourcePreference p) async {
    final current = p.read(_saved);
    final picked = await showAdaptiveModal<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
              child: Text(
                p.title,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            for (var i = 0; i < p.values.length; i++)
              ListTile(
                title: Text(
                  p.entries[i],
                  style: TextStyle(color: AppColors.textPrimary),
                ),
                trailing: p.values[i] == current
                    ? Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.of(ctx).pop(p.values[i]),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await _set(p.key, picked);
  }

  @override
  Widget build(BuildContext context) {
    final prefs = _prefs;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 8, 4),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded, color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'ext.settings_title'.tr(args: [widget.source.name]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (_saved.isNotEmpty && (prefs?.isNotEmpty ?? false))
                    TextButton(
                      onPressed: _reset,
                      child: Text('ext.settings_reset'.tr()),
                    ),
                ],
              ),
            ),
            Flexible(child: _body(prefs)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _body(List<SourcePreference>? prefs) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'ext.settings_failed'.tr(),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    if (prefs == null) {
      return const Padding(
        padding: EdgeInsets.all(28),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (prefs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'ext.settings_none'.tr(),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    TextStyle title = TextStyle(
      color: AppColors.textPrimary,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );
    TextStyle sub = TextStyle(color: AppColors.textSecondary, fontSize: 12);
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      children: [
        for (final p in prefs)
          switch (p) {
            SwitchSourcePreference() => SwitchListTile(
              title: Text(p.title, style: title),
              subtitle: p.summary.isEmpty ? null : Text(p.summary, style: sub),
              value: p.read(_saved),
              onChanged: (v) => _set(p.key, v),
            ),
            ListSourcePreference() => ListTile(
              title: Text(p.title, style: title),
              subtitle: Text(p.labelOf(p.read(_saved)), style: sub),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _pickOne(p),
            ),
            MultiSourcePreference() => ExpansionTile(
              title: Text(p.title, style: title),
              subtitle: Text(
                p.read(_saved).isEmpty
                    ? '—'
                    : [
                        for (var i = 0; i < p.values.length; i++)
                          if (p.read(_saved).contains(p.values[i]))
                            p.entries[i],
                      ].join(', '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sub,
              ),
              children: [
                for (var i = 0; i < p.values.length; i++)
                  CheckboxListTile(
                    dense: true,
                    title: Text(p.entries[i]),
                    value: p.read(_saved).contains(p.values[i]),
                    onChanged: (on) {
                      final next = {...p.read(_saved)};
                      on == true
                          ? next.add(p.values[i])
                          : next.remove(p.values[i]);
                      _set(p.key, next.toList());
                    },
                  ),
              ],
            ),
            TextSourcePreference() => ListTile(
              title: Text(p.title, style: title),
              subtitle: Text(
                p.read(_saved).isEmpty ? '—' : p.read(_saved),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: sub,
              ),
              trailing: const Icon(Icons.edit_outlined, size: 18),
              onTap: () => _editText(p),
            ),
          },
      ],
    );
  }
}
