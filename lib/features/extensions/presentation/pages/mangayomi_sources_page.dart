import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/extensions/data/mangayomi_repo_store.dart';
import 'package:soplay/features/extensions/data/mangayomi_runtime.dart';
import 'package:soplay/features/extensions/domain/entities/extension_repo_entity.dart';
import 'package:soplay/features/extensions/domain/entities/mangayomi_source.dart';
import 'package:soplay/features/extensions/domain/mangayomi_source_filter.dart';
import 'package:soplay/features/extensions/presentation/pages/mangayomi_source_picker_page.dart';
import 'package:soplay/features/extensions/presentation/widgets/recommended_repos_section.dart';
import 'package:soplay/features/extensions/presentation/widgets/source_filter_chips.dart';
import 'package:soplay/features/extensions/presentation/widgets/source_settings_sheet.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';

/// Sources page for Mangayomi JavaScript extensions.
///
/// The one extension page that is **not** Android-only. CloudStream, Aniyomi and
/// Mihon extensions are Android APKs; these are `.js` files run in the headless
/// WebView, so this screen — and everything installed through it — works on iOS,
/// macOS and Windows too.
class MangayomiSourcesPage extends StatefulWidget {
  const MangayomiSourcesPage({super.key});

  @override
  State<MangayomiSourcesPage> createState() => _MangayomiSourcesPageState();
}

class _MangayomiSourcesPageState extends State<MangayomiSourcesPage> {
  static const Color _accent = Color(0xFFE5484D);
  static const String _logo =
      'https://raw.githubusercontent.com/kodjodevf/mangayomi/main/assets/app_icons/icon-red.png';

  late final MangayomiRepoStore _store = getIt<MangayomiRepoStore>();
  late final HiveService _hive = getIt<HiveService>();

  final _controller = TextEditingController();
  bool _busy = false;
  String? _status;
  bool _statusError = false;
  MangayomiItemType? _type;
  List<String> _languages = const [];

  List<String> get _repos => _store.repos();

  /// Installed sources the user may see, before the type and language filters.
  List<MangayomiSource> get _installed =>
      MangayomiSourceFilter(includeNsfw: _hive.showAdultContent)
          .apply(_store.sources());

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reloadProviders() {
    try {
      context.read<ProviderBloc>().add(const ProviderLoad());
    } catch (_) {}
  }

  Future<void> _add() => _install([_controller.text.trim()]);

  /// Fetches one or more sibling indexes (manga / anime / novel), lets the
  /// user pick sources from them, and installs only those.
  Future<void> _install(List<String> urls) async {
    final list = urls.where((u) => u.trim().isNotEmpty).toList();
    if (list.isEmpty || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _statusError = false;
      _status = 'ext.loading_repo'.tr();
    });

    final indexes = <MangayomiRepoIndex>[];
    final failures = <String>[];
    for (final url in list) {
      try {
        indexes.add(await _store.fetchIndex(url));
      } catch (e) {
        // A repo publishing only some of the three sibling indexes is normal —
        // record the miss and keep going rather than failing the whole install.
        failures.add('${url.split('/').last}: $e');
      }
    }
    if (!mounted) return;

    final skippedDart = indexes.fold<int>(0, (n, i) => n + i.skippedDart);
    if (indexes.every((i) => i.sources.isEmpty)) {
      setState(() {
        _busy = false;
        _statusError = true;
        _status = indexes.isEmpty && failures.isNotEmpty
            ? 'ext.could_not_install'.tr(args: [failures.first])
            : _withDartNote('ext.none_found_js'.tr(), skippedDart);
      });
      return;
    }

    setState(() {
      _busy = false;
      _status = null;
    });
    final chosen = await MangayomiSourcePickerPage.show(
      context,
      indexes: indexes,
      installedIds: _store.sources().map((s) => s.id).toSet(),
      initialLanguages: _hive.getProviderLanguages(),
      includeNsfw: _hive.showAdultContent,
    );
    if (!mounted || chosen == null || chosen.isEmpty) return;

    setState(() {
      _busy = true;
      _status = 'ext.installing_extensions'.tr();
    });
    var added = 0;
    String? error;
    try {
      for (final index in indexes) {
        final ids = chosen[index.url];
        if (ids == null || ids.isEmpty) continue;
        final res = await _store.installSources(index, ids);
        added += res['added'] ?? 0;
      }
    } catch (e) {
      error = '$e';
    }

    if (!mounted) return;
    if (added > 0) {
      _controller.clear();
      _reloadProviders();
    }
    setState(() {
      _busy = false;
      _statusError = error != null;
      _status = error != null
          ? 'ext.could_not_install'.tr(args: [error])
          : _withDartNote(
              'ext.added_sources'.tr(args: ['$added']),
              skippedDart,
            );
    });
  }

  static String _withDartNote(String status, int skippedDart) =>
      skippedDart > 0
      ? '$status ${'ext.skipped_dart'.tr(args: ['$skippedDart'])}'
      : status;

  Future<bool> _confirm(String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        content: Text(message),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('general.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'ext.remove'.tr(),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _remove(String url) async {
    if (!await _confirm('ext.remove_repo_confirm'.tr())) return;
    await _store.removeRepo(url);
    getIt<MangayomiRuntime>().invalidate();
    if (!mounted) return;
    _reloadProviders();
    setState(() {
      _statusError = false;
      _status = 'ext.repo_removed'.tr();
    });
  }

  Future<void> _removeSource(MangayomiSource s) async {
    if (!await _confirm('ext.remove_source_confirm'.tr(args: [s.name]))) {
      return;
    }
    await _store.removeSource(s.id);
    getIt<MangayomiRuntime>().invalidate(s.id);
    if (!mounted) return;
    _reloadProviders();
    setState(() {
      _statusError = false;
      _status = 'ext.source_removed'.tr();
    });
  }

  Future<void> _setEnabled(MangayomiSource s, bool enabled) async {
    await _store.setEnabled(s.id, enabled);
    if (!mounted) return;
    _reloadProviders();
    setState(() {});
  }

  Future<void> _checkUpdates() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _statusError = false;
      _status = 'ext.checking_extension_updates'.tr();
    });
    try {
      final result = await _store.checkUpdates();
      if (!mounted) return;
      if (result.added > 0) _reloadProviders();
      final lines = <String>[
        if (result.updates.isNotEmpty)
          'ext.updates_available'.tr(args: ['${result.updates.length}'])
        else if (result.failures.isEmpty)
          'ext.all_up_to_date'.tr(),
        if (result.added > 0) 'ext.added_sources'.tr(args: ['${result.added}']),
        for (final e in result.failures.entries)
          'ext.repo_check_failed'.tr(args: [e.key.split('/').last, e.value]),
      ];
      setState(() {
        _statusError = result.failures.isNotEmpty;
        _status = lines.join('\n');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusError = true;
        _status = 'ext.update_check_failed'.tr(args: ['$e']);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Applies pending updates for [ids], or every pending one when null.
  Future<void> _applyUpdates([List<String>? ids]) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _statusError = false;
      _status = 'ext.installing_extensions'.tr();
    });
    try {
      final applied = await _store.applyUpdates(ids);
      // Extension code is cached per version, but the runtime also holds the
      // compiled instance in memory.
      final runtime = getIt<MangayomiRuntime>();
      for (final id in applied) {
        runtime.invalidate(id);
      }
      if (!mounted) return;
      if (applied.isNotEmpty) _reloadProviders();
      setState(() {
        _status = 'ext.updated_count'.tr(args: ['${applied.length}']);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusError = true;
        _status = 'ext.update_check_failed'.tr(args: ['$e']);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!MangayomiRuntime.isSupported) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          title: Text('ext.mangayomi_title'.tr()),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'ext.needs_webview'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }
    final installed = _installed;
    final byType = MangayomiSourceFilter(type: _type).apply(installed);
    final sources = MangayomiSourceFilter(
      type: _type,
      languages: _languages,
    ).apply(installed);
    final updates = _store.availableUpdates();
    final disabled = _store.disabledIds();
    final repos = _repos;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Text('ext.mangayomi_title'.tr()),
        actions: [
          IconButton(
            tooltip: 'ext.check_extension_updates'.tr(),
            icon: const Icon(Icons.system_update_alt_rounded),
            onPressed: (_busy || repos.isEmpty) ? null : _checkUpdates,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _header(),
          const SizedBox(height: 16),
          _addCard(),
          if (_status != null) ...[
            const SizedBox(height: 12),
            _statusBanner(),
          ],
          const SizedBox(height: 24),
          RecommendedReposSection(
            kind: ExtensionRepoKind.mangayomi,
            installedUrls: repos.toSet(),
            busy: _busy,
            accent: _accent,
            fallbackIcon: _logo,
            nsfwAllowed: _hive.showAdultContent,
            onInstall: (repo) => _install(repo.allUrls),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text('ext.installed_repos'.tr(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textHint, letterSpacing: 1)),
              const Spacer(),
              if (repos.isNotEmpty)
                Text('${repos.length}',
                    style: const TextStyle(color: AppColors.textHint)),
            ],
          ),
          const SizedBox(height: 8),
          if (repos.isEmpty) _empty() else ...repos.map(_repoTile),
          if (installed.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                const Icon(Icons.javascript_outlined, size: 16, color: _accent),
                const SizedBox(width: 6),
                Text('ext.sources_heading'.tr(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textHint, letterSpacing: 1)),
                const Spacer(),
                Text(
                    sources.length == installed.length
                        ? '${installed.length}'
                        : '${sources.length} / ${installed.length}',
                    style: const TextStyle(color: AppColors.textHint)),
              ],
            ),
            if (updates.isNotEmpty) ...[
              const SizedBox(height: 8),
              _updatesBanner(updates.length),
            ],
            const SizedBox(height: 4),
            MangayomiTypeFilterRow(
              padding: EdgeInsets.zero,
              selected: _type,
              onSelected: (t) => setState(() => _type = t),
            ),
            MangayomiLanguageFilterRow(
              padding: EdgeInsets.zero,
              counts: MangayomiSourceFilter.languageCounts(byType),
              selected: _languages,
              onToggle: (code) => setState(
                () => _languages =
                    MangayomiSourceFilter.toggleLanguage(_languages, code),
              ),
            ),
            const SizedBox(height: 8),
            if (sources.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text('ext.no_matches'.tr(),
                      style: const TextStyle(color: AppColors.textHint)),
                ),
              )
            else
              ...sources.map((s) => _sourceTile(
                    s,
                    update: updates[s.id],
                    enabled: !disabled.contains(s.id),
                  )),
          ],
        ],
      ),
    );
  }

  Widget _header() => Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Image.network(_logo,
                width: 44,
                height: 44,
                cacheWidth: 132,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                      width: 44,
                      height: 44,
                      color: AppColors.surfaceVariant,
                      child: const Icon(Icons.javascript_outlined,
                          color: AppColors.textHint),
                    )),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'ext.mangayomi_desc'.tr(),
              style: const TextStyle(
                  color: AppColors.textHint, fontSize: 12.5, height: 1.35),
            ),
          ),
        ],
      );

  Widget _addCard() => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              enabled: !_busy,
              cursorColor: _accent,
              style: const TextStyle(color: Colors.white),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'ext.index_url'.tr(),
                labelStyle: const TextStyle(color: AppColors.textHint),
                floatingLabelStyle: const TextStyle(color: _accent),
                hintText: 'https://…/index.json',
                hintStyle: const TextStyle(color: AppColors.textHint),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                      color: _accent.withValues(alpha: 0.6), width: 1.4),
                ),
              ),
              onSubmitted: (_) => _add(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 46,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                ),
                onPressed: _busy ? null : _add,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add),
                label: Text(_busy ? 'ext.installing'.tr() : 'ext.add_repo'.tr()),
              ),
            ),
          ],
        ),
      );

  Widget _statusBanner() {
    final color = _statusError ? AppColors.error : AppColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          if (_busy)
            const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2))
          else
            Icon(_statusError ? Icons.error_outline : Icons.check_circle_outline,
                size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_status!,
                style: TextStyle(color: color, fontSize: 12.5, height: 1.3)),
          ),
        ],
      ),
    );
  }

  Widget _empty() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            const Icon(Icons.cloud_off_outlined,
                color: AppColors.textHint, size: 32),
            const SizedBox(height: 8),
            Text('ext.no_repos_yet'.tr(),
                style: const TextStyle(color: AppColors.textHint)),
          ],
        ),
      );

  Widget _repoTile(String url) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: const Icon(Icons.folder_outlined, color: _accent),
            title: Text(
              url.split('/').last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600),
            ),
            subtitle: Text(url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(color: AppColors.textHint, fontSize: 11)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'ext.add_sources'.tr(),
                  icon: const Icon(Icons.playlist_add_rounded,
                      color: AppColors.textSecondary),
                  onPressed: _busy ? null : () => _install([url]),
                ),
                IconButton(
                  tooltip: 'ext.remove'.tr(),
                  icon: const Icon(Icons.delete_outline,
                      color: AppColors.error),
                  onPressed: _busy ? null : () => _remove(url),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _updatesBanner(int count) => Container(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 6, 6),
        decoration: BoxDecoration(
          color: _accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _accent.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.system_update_alt_rounded,
                size: 16, color: _accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'ext.updates_available'.tr(args: ['$count']),
                style: const TextStyle(color: Colors.white, fontSize: 12.5),
              ),
            ),
            TextButton(
              onPressed: _busy ? null : () => _applyUpdates(),
              child: Text('ext.update_all'.tr(),
                  style: const TextStyle(color: _accent)),
            ),
          ],
        ),
      );

  Widget _sourceTile(
    MangayomiSource s, {
    MangayomiSource? update,
    bool enabled = true,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Opacity(
                  opacity: enabled ? 1 : 0.45,
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Image.network(
                          s.iconUrl.isEmpty ? _logo : s.iconUrl,
                          width: 26,
                          height: 26,
                          cacheWidth: 78,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 26,
                            height: 26,
                            color: AppColors.surfaceVariant,
                            child: const Icon(Icons.public,
                                size: 14, color: AppColors.textHint),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(s.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 13)),
                                ),
                                if (s.isNsfw) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: AppColors.error.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('18+',
                                        style: TextStyle(
                                            color: AppColors.error,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              [
                                s.lang.toUpperCase(),
                                _typeLabel(s.itemType),
                                update == null
                                    ? 'v${s.version}'
                                    : 'v${s.version} → v${update.version}',
                                if (!enabled) 'ext.source_disabled'.tr(),
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.textHint, fontSize: 10.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (update != null)
                TextButton(
                  onPressed: _busy ? null : () => _applyUpdates([s.id]),
                  style: TextButton.styleFrom(
                    foregroundColor: _accent,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text('ext.update'.tr()),
                ),
              // The source's own settings — its domain, preferred quality,
              // what it hides.
              IconButton(
                tooltip: 'ext.settings'.tr(),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.tune_rounded,
                    size: 19, color: AppColors.textSecondary),
                onPressed: () => SourceSettingsSheet.show(context, s),
              ),
              PopupMenuButton<_SourceAction>(
                enabled: !_busy,
                icon: const Icon(Icons.more_vert_rounded,
                    size: 19, color: AppColors.textSecondary),
                color: AppColors.surface,
                onSelected: (a) => switch (a) {
                  _SourceAction.toggle => _setEnabled(s, !enabled),
                  _SourceAction.remove => _removeSource(s),
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: _SourceAction.toggle,
                    child: Text(enabled
                        ? 'ext.disable_source'.tr()
                        : 'ext.enable_source'.tr()),
                  ),
                  PopupMenuItem(
                    value: _SourceAction.remove,
                    child: Text('ext.remove_source'.tr(),
                        style: const TextStyle(color: AppColors.error)),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  static String _typeLabel(MangayomiItemType t) => switch (t) {
        MangayomiItemType.anime => 'ext.type_anime'.tr(),
        MangayomiItemType.novel => 'ext.type_novel'.tr(),
        MangayomiItemType.manga => 'ext.type_manga'.tr(),
      };
}

enum _SourceAction { toggle, remove }
