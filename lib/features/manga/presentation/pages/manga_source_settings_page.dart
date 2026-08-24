import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/manga/manga_channel.dart';
import 'package:soplay/core/theme/app_colors.dart';

class MangaSourceSettingsPage extends StatefulWidget {
  final String sourceId;
  final String name;
  const MangaSourceSettingsPage({
    super.key,
    required this.sourceId,
    required this.name,
  });

  @override
  State<MangaSourceSettingsPage> createState() =>
      _MangaSourceSettingsPageState();
}

class _MangaSourceSettingsPageState extends State<MangaSourceSettingsPage> {
  /// The manga screens used to carry their own private blue. There is one
  /// accent in the app now, and the user chooses it.
  static Color get _accent => AppColors.primary;

  List<Map<String, dynamic>> _prefs = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final raw = await MangaChannel.getPreferences(widget.sourceId);
    if (!mounted) return;
    setState(() {
      _prefs = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _loading = false;
    });
  }

  Future<void> _save(String key, Object? value, String type) async {
    await MangaChannel.setPreference(widget.sourceId, key, value, type);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Text(widget.name),
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: _accent, strokeWidth: 2))
          : _prefs.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      'manga.no_preferences'.tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textHint),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _prefs.length,
                  separatorBuilder: (_, _) => const Divider(
                      height: 1, color: Colors.white10, indent: 16, endIndent: 16),
                  itemBuilder: (context, i) => _tile(_prefs[i]),
                ),
    );
  }

  Widget _tile(Map<String, dynamic> p) {
    final type = p['type'] as String? ?? 'info';
    final key = p['key'] as String? ?? '';
    final title = (p['title'] as String?)?.trim();
    final summary = (p['summary'] as String?)?.trim();

    switch (type) {
      case 'switch':
        final value = p['value'] == true;
        return SwitchListTile(
          activeThumbColor: _accent,
          title: Text(title?.isNotEmpty == true ? title! : key,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: summary?.isNotEmpty == true
              ? Text(summary!,
                  style: const TextStyle(
                      color: AppColors.textHint, fontSize: 12))
              : null,
          value: value,
          onChanged: (v) {
            setState(() => p['value'] = v);
            _save(key, v, 'switch');
          },
        );

      case 'list':
        final entries = (p['entries'] as List?)?.cast<dynamic>() ?? const [];
        final values = (p['entryValues'] as List?)?.cast<dynamic>() ?? const [];
        final current = p['value']?.toString() ?? '';
        final idx = values.indexWhere((e) => e.toString() == current);
        final label = idx >= 0 && idx < entries.length
            ? entries[idx].toString()
            : current;
        return ListTile(
          title: Text(title?.isNotEmpty == true ? title! : key,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: Text(label.isNotEmpty ? label : (summary ?? ''),
              style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
          trailing: const Icon(Icons.expand_more, color: AppColors.textHint),
          onTap: () => _pickList(p, key, entries, values, current),
        );

      case 'multi':
        final entries = (p['entries'] as List?)?.cast<dynamic>() ?? const [];
        final values = (p['entryValues'] as List?)?.cast<dynamic>() ?? const [];
        final current =
            ((p['value'] as List?) ?? const []).map((e) => e.toString()).toSet();
        return ListTile(
          title: Text(title?.isNotEmpty == true ? title! : key,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: Text(
            current.isEmpty
                ? (summary?.isNotEmpty == true
                    ? summary!
                    : 'manga.not_selected'.tr())
                : 'manga.n_selected'.tr(args: ['${current.length}']),
            style: const TextStyle(color: AppColors.textHint, fontSize: 12),
          ),
          trailing: const Icon(Icons.checklist, color: AppColors.textHint),
          onTap: () => _pickMulti(p, key, entries, values, current),
        );

      case 'text':
        final current = p['value']?.toString() ?? '';
        return ListTile(
          title: Text(title?.isNotEmpty == true ? title! : key,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: Text(
            current.isNotEmpty ? current : (summary ?? ''),
            style: const TextStyle(color: AppColors.textHint, fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.edit_outlined,
              color: AppColors.textHint, size: 18),
          onTap: () => _editText(p, key, title ?? key, current),
        );

      default:
        return ListTile(
          title: Text(title?.isNotEmpty == true ? title! : key,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: summary?.isNotEmpty == true
              ? Text(summary!,
                  style: const TextStyle(
                      color: AppColors.textHint, fontSize: 12))
              : null,
        );
    }
  }

  Future<void> _pickList(Map<String, dynamic> p, String key, List entries,
      List values, String current) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        backgroundColor: AppColors.surface,
        title: Text(p['title']?.toString() ?? key,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        children: [
          for (var i = 0; i < entries.length; i++)
            Builder(builder: (context) {
              final value = i < values.length
                  ? values[i].toString()
                  : entries[i].toString();
              final isSelected = value == current;
              return ListTile(
                dense: true,
                title: Text(entries[i].toString(),
                    style:
                        const TextStyle(color: Colors.white, fontSize: 14)),
                trailing: isSelected
                    ? Icon(Icons.check, color: _accent, size: 20)
                    : null,
                onTap: () => Navigator.of(context).pop(value),
              );
            }),
        ],
      ),
    );
    if (picked != null && picked != current) {
      setState(() => p['value'] = picked);
      _save(key, picked, 'list');
    }
  }

  Future<void> _pickMulti(Map<String, dynamic> p, String key, List entries,
      List values, Set<String> current) async {
    final selected = Set<String>.from(current);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(p['title']?.toString() ?? key,
              style: const TextStyle(color: Colors.white, fontSize: 16)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (var i = 0; i < entries.length; i++)
                  CheckboxListTile(
                    activeColor: _accent,
                    dense: true,
                    title: Text(entries[i].toString(),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14)),
                    value: selected.contains(
                        i < values.length ? values[i].toString() : ''),
                    onChanged: (v) {
                      final val =
                          i < values.length ? values[i].toString() : '';
                      setLocal(() {
                        if (v == true) {
                          selected.add(val);
                        } else {
                          selected.remove(val);
                        }
                      });
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('general.cancel'.tr())),
            TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text('general.save'.tr())),
          ],
        ),
      ),
    );
    if (ok == true) {
      setState(() => p['value'] = selected.toList());
      _save(key, selected.toList(), 'multi');
    }
  }

  Future<void> _editText(Map<String, dynamic> p, String key, String title,
      String current) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintStyle: TextStyle(color: AppColors.textHint),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: _accent)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('general.cancel'.tr())),
          TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text),
              child: Text('general.save'.tr())),
        ],
      ),
    );
    controller.dispose();
    if (result != null && result != current) {
      setState(() => p['value'] = result);
      _save(key, result, 'text');
    }
  }
}
