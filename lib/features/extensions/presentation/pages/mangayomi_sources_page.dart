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
import 'package:soplay/features/extensions/presentation/widgets/recommended_repos_section.dart';
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

  List<String> get _repos => _store.repos();

  List<MangayomiSource> get _sources {
    // `.toList()` on BOTH branches. `store.sources()` returns a const empty
    // list when nothing is installed, and `List.sort` on an unmodifiable list
    // throws "Cannot modify an unmodifiable list" regardless of length — so
    // sorting the branch that passed the original list straight through blew up
    // the whole page for any user with adult sources enabled and no sources yet.
    final all = _store.sources();
    final visible = _hive.showNsfwMangaSources
        ? all.toList()
        : all.where((s) => !s.isNsfw).toList();
    visible.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return visible;
  }

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

  /// Installs one or more sibling indexes (manga / anime / novel) as one unit.
  Future<void> _install(List<String> urls) async {
    final list = urls.where((u) => u.trim().isNotEmpty).toList();
    if (list.isEmpty || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _statusError = false;
      _status = 'ext.installing_extensions'.tr();
    });

    var added = 0;
    var skippedDart = 0;
    final failures = <String>[];
    for (final url in list) {
      try {
        final res = await _store.addRepo(url);
        added += res['added'] ?? 0;
        skippedDart += res['skippedDart'] ?? 0;
      } catch (e) {
        // A repo publishing only some of the three sibling indexes is normal —
        // record the miss and keep going rather than failing the whole install.
        failures.add('${url.split('/').last}: $e');
      }
    }

    if (!mounted) return;
    if (added > 0) {
      _controller.clear();
      _reloadProviders();
    }
    setState(() {
      _busy = false;
      _statusError = added == 0;
      if (added == 0) {
        _status = failures.isEmpty
            ? 'ext.none_found_js'.tr()
            : 'ext.could_not_install'.tr(args: [failures.first]);
      } else {
        _status = 'ext.added_sources'.tr(args: ['$added']);
        if (skippedDart > 0) {
          _status = '$_status '
              '${'ext.skipped_dart'.tr(args: ['$skippedDart'])}';
        }
      }
    });
  }

  Future<void> _remove(String url) async {
    await _store.removeRepo(url);
    if (!mounted) return;
    _reloadProviders();
    setState(() {
      _statusError = false;
      _status = 'ext.repo_removed'.tr();
    });
  }

  Future<void> _checkUpdates() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _statusError = false;
      _status = 'ext.checking_extension_updates'.tr();
    });
    try {
      final count = await _store.checkUpdates();
      // Extension code is cached per version; a bump invalidates it, but the
      // runtime also holds one loaded in memory.
      getIt<MangayomiRuntime>().invalidate();
      if (!mounted) return;
      if (count > 0) _reloadProviders();
      setState(() {
        _statusError = false;
        _status = count == 0
            ? 'ext.all_up_to_date'.tr()
            : 'ext.updated_count'.tr(args: ['$count']);
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
        appBar: AppBar(title: Text('ext.mangayomi_title'.tr())),
        body: Center(
          child: Text('ext.needs_webview'.tr()),
        ),
      );
    }
    final sources = _sources;
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
            nsfwAllowed: _hive.showNsfwMangaSources,
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
          if (sources.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                const Icon(Icons.javascript_outlined, size: 16, color: _accent),
                const SizedBox(width: 6),
                Text('ext.sources_heading'.tr(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textHint, letterSpacing: 1)),
                const Spacer(),
                Text('${sources.length}',
                    style: const TextStyle(color: AppColors.textHint)),
              ],
            ),
            const SizedBox(height: 8),
            ...sources.map(_sourceTile),
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
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                      width: 44,
                      height: 44,
                      color: Colors.white10,
                      child: const Icon(Icons.javascript_outlined,
                          color: Colors.white54),
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
    final color = _statusError ? Colors.redAccent : Colors.green;
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
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: _busy ? null : () => _remove(url),
            ),
          ),
        ),
      );

  Widget _sourceTile(MangayomiSource s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Image.network(
                  s.iconUrl.isEmpty ? _logo : s.iconUrl,
                  width: 26,
                  height: 26,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 26,
                    height: 26,
                    color: Colors.white10,
                    child: const Icon(Icons.public,
                        size: 14, color: Colors.white54),
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
                              color: Colors.redAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('18+',
                                style: TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      '${s.lang.toUpperCase()} · ${_typeLabel(s.itemType)} · v${s.version}',
                      style: const TextStyle(
                          color: AppColors.textHint, fontSize: 10.5),
                    ),
                  ],
                ),
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
