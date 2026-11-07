import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/extensions/data/zangetsu_repo_store.dart';
import 'package:soplay/features/extensions/domain/entities/extension_repo_entity.dart';
import 'package:soplay/features/extensions/domain/entities/zangetsu_source.dart';
import 'package:soplay/features/extensions/presentation/widgets/recommended_repos_section.dart';
import 'package:soplay/features/extensions/presentation/widgets/source_filter_chips.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';
import 'package:soplay/features/sources/domain/source_scope.dart';

/// Sources from external Zangetsu repos, run on the device. Sources Sozo
/// already ships are listed as built in and keep using Sozo's own copy.
class ZangetsuSourcesPage extends StatefulWidget {
  const ZangetsuSourcesPage({super.key});

  @override
  State<ZangetsuSourcesPage> createState() => _ZangetsuSourcesPageState();
}

class _ZangetsuSourcesPageState extends State<ZangetsuSourcesPage> {
  static const Color _accent = Color(0xFF7C5CFF);

  late final ZangetsuRepoStore _store = getIt<ZangetsuRepoStore>();
  late final HiveService _hive = getIt<HiveService>();

  final _urlController = TextEditingController();
  final _searchController = TextEditingController();
  bool _busy = false;
  String? _status;
  bool _statusError = false;
  String _type = 'all';
  String _lang = 'all';

  @override
  void initState() {
    super.initState();
    if (_store.repos().isNotEmpty) _refresh(silent: true);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool get _adult => _hive.showAdultContent;

  List<ZangetsuSource> get _allSources {
    final out = <ZangetsuSource>[];
    for (final repo in _store.repos()) {
      out.addAll(_store.manifest(repo).where((s) => _adult || !s.nsfw));
    }
    return out;
  }

  List<ZangetsuSource> _visible(List<ZangetsuSource> all) {
    final q = _searchController.text.trim().toLowerCase();
    final list = all.where((s) {
      if (_type == 'anime' && !s.isAnime) return false;
      if (_type == 'movies' && s.isAnime) return false;
      if (_lang != 'all' && s.lang != _lang) return false;
      return q.isEmpty ||
          s.name.toLowerCase().contains(q) ||
          s.id.contains(q);
    }).toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  void _reloadProviders() {
    try {
      context.read<ProviderBloc>().add(const ProviderLoad());
    } catch (_) {}
  }

  void _setStatus(String text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _status = text;
      _statusError = error;
    });
  }

  String _errorText(Object e) {
    final kind = e is ZangetsuRepoException
        ? e.error
        : ZangetsuRepoError.unreachable;
    return switch (kind) {
      ZangetsuRepoError.invalidUrl => 'zangetsu.error_invalid_url'.tr(),
      ZangetsuRepoError.unreachable => 'zangetsu.error_unreachable'.tr(),
      ZangetsuRepoError.invalidIndex => 'zangetsu.error_invalid_index'.tr(),
    };
  }

  Future<void> _addRepo(String raw) async {
    final url = raw.trim();
    if (url.isEmpty || _busy) return;
    FocusScope.of(context).unfocus();
    if (!ZangetsuRepoStore.isAllowedUrl(url)) {
      _setStatus('zangetsu.error_invalid_url'.tr(), error: true);
      return;
    }
    setState(() {
      _busy = true;
      _status = 'zangetsu.loading_repo'.tr();
      _statusError = false;
    });
    try {
      final sources = await _store.addRepo(url);
      if (!mounted) return;
      _urlController.clear();
      final count = sources.where((s) => _adult || !s.nsfw).length;
      _setStatus('zangetsu.repo_added'.tr(args: ['$count']));
    } catch (e) {
      _setStatus(_errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeRepo(String url) async {
    await _store.removeRepo(url);
    _reloadProviders();
    _setStatus('ext.repo_removed'.tr());
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      if (!silent) {
        _status = 'zangetsu.checking'.tr();
        _statusError = false;
      }
    });
    await _store.refreshAll();
    if (!mounted) return;
    setState(() => _busy = false);
    if (silent) return;
    final pending = _store.updates().length;
    _setStatus(
      pending == 0
          ? 'ext.all_up_to_date'.tr()
          : 'zangetsu.updates_available'.tr(args: ['$pending']),
    );
  }

  Future<void> _install(ZangetsuSource s) async {
    await _store.install(s);
    _reloadProviders();
    _setStatus('zangetsu.installed_one'.tr(args: [s.name]));
  }

  Future<void> _remove(ZangetsuSource s) async {
    await _store.remove(s.providerId);
    _reloadProviders();
    _setStatus('zangetsu.removed_one'.tr(args: [s.name]));
  }

  Future<void> _toggle(ZangetsuSource s, bool enabled) async {
    await _store.setEnabled(s.providerId, enabled);
    _reloadProviders();
    if (mounted) setState(() {});
  }

  Future<void> _update(ZangetsuSource s) async {
    if (await _store.update(s.providerId)) {
      _reloadProviders();
      _setStatus('zangetsu.updated'.tr(args: ['1']));
    }
  }

  Future<void> _updateAll() async {
    if (_busy) return;
    setState(() => _busy = true);
    final count = await _store.updateAll();
    if (!mounted) return;
    setState(() => _busy = false);
    if (count > 0) _reloadProviders();
    _setStatus(
      count == 0
          ? 'ext.all_up_to_date'.tr()
          : 'zangetsu.updated'.tr(args: ['$count']),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repos = _store.repos();
    final all = _allSources;
    final langs = {for (final s in all) s.lang}.toList()..sort();
    if (_lang != 'all' && !langs.contains(_lang)) _lang = 'all';
    final visible = _visible(all);
    final installed = {for (final s in _store.installed()) s.providerId: s};
    final updates = _store.updates();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Text('zangetsu.title'.tr()),
        actions: [
          IconButton(
            tooltip: 'ext.check_updates'.tr(),
            icon: const Icon(Icons.refresh_rounded),
            onPressed: (_busy || repos.isEmpty) ? null : _refresh,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'zangetsu.desc'.tr(),
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          _addCard(),
          if (_status != null) ...[
            const SizedBox(height: 12),
            _statusBanner(),
          ],
          const SizedBox(height: 24),
          RecommendedReposSection(
            kind: ExtensionRepoKind.zangetsu,
            installedUrls: repos.toSet(),
            busy: _busy,
            accent: _accent,
            fallbackIcon: '',
            nsfwAllowed: _adult,
            onInstall: (repo) => _addRepo(repo.url),
          ),
          const SizedBox(height: 24),
          _label('ext.installed_repos'.tr(), repos.length),
          const SizedBox(height: 8),
          if (repos.isEmpty) _empty() else ...repos.map(_repoTile),
          if (all.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: _label('ext.sources_heading'.tr(), all.length)),
                if (updates.isNotEmpty)
                  TextButton.icon(
                    onPressed: _busy ? null : _updateAll,
                    icon: const Icon(Icons.system_update_alt_rounded, size: 16),
                    label: Text(
                      'zangetsu.update_all'.tr(args: ['${updates.length}']),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _filters(langs),
            const SizedBox(height: 8),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'ext.no_matches'.tr(),
                    style: const TextStyle(color: AppColors.textHint),
                  ),
                ),
              )
            else
              ...visible.map((s) => _sourceTile(s, installed[s.providerId])),
          ],
        ],
      ),
    );
  }

  Widget _label(String text, int count) => Row(
    children: [
      Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.textHint,
          letterSpacing: 1,
        ),
      ),
      const Spacer(),
      if (count > 0)
        Text('$count', style: const TextStyle(color: AppColors.textHint)),
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
          controller: _urlController,
          enabled: !_busy,
          cursorColor: _accent,
          keyboardType: TextInputType.url,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration(
            label: 'ext.index_url'.tr(),
            hint: 'https://raw.githubusercontent.com/…/index.json',
          ),
          onSubmitted: _addRepo,
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 46,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
            ),
            onPressed: _busy ? null : () => _addRepo(_urlController.text),
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.add),
            label: Text('ext.add_repo'.tr()),
          ),
        ),
      ],
    ),
  );

  InputDecoration _inputDecoration({
    String? label,
    required String hint,
    Widget? prefix,
  }) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: AppColors.textHint),
    floatingLabelStyle: const TextStyle(color: _accent),
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.textHint),
    prefixIcon: prefix,
    isDense: true,
    filled: true,
    fillColor: AppColors.background,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: _accent.withValues(alpha: 0.6), width: 1.4),
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
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              _statusError ? Icons.error_outline : Icons.check_circle_outline,
              size: 16,
              color: color,
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _status!,
              style: TextStyle(color: color, fontSize: 12.5, height: 1.3),
            ),
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
        const Icon(
          Icons.cloud_off_outlined,
          color: AppColors.textHint,
          size: 32,
        ),
        const SizedBox(height: 8),
        Text(
          'ext.no_repos_yet'.tr(),
          style: const TextStyle(color: AppColors.textHint),
        ),
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
          repoLabel(url),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          url,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textHint, fontSize: 11),
        ),
        trailing: IconButton(
          tooltip: 'general.remove'.tr(),
          icon: const Icon(Icons.delete_outline, color: AppColors.error),
          onPressed: _busy ? null : () => _removeRepo(url),
        ),
      ),
    ),
  );

  Widget _filters(List<String> langs) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _searchController,
        cursorColor: _accent,
        style: const TextStyle(color: Colors.white),
        onChanged: (_) => setState(() {}),
        decoration: _inputDecoration(
          hint: 'zangetsu.search'.tr(),
          prefix: const Icon(Icons.search, color: AppColors.textHint),
        ),
      ),
      const SizedBox(height: 4),
      // The same chip rows as the Mangayomi page and the catalog.
      SourceFilterChipRow(
        padding: EdgeInsets.zero,
        options: [
          for (final (value, label) in [
            ('all', 'zangetsu.all_types'.tr()),
            ('anime', 'ext.type_anime'.tr()),
            ('movies', 'zangetsu.type_movies'.tr()),
          ])
            SourceFilterOption(
              label: label,
              active: _type == value,
              onTap: () => setState(() => _type = value),
            ),
        ],
      ),
      if (langs.length > 1)
        SourceFilterChipRow(
          padding: EdgeInsets.zero,
          options: [
            for (final lang in ['all', ...langs])
              SourceFilterOption(
                label: lang == 'all'
                    ? 'zangetsu.all_languages'.tr()
                    : lang.toUpperCase(),
                active: _lang == lang,
                onTap: () => setState(() => _lang = lang),
              ),
          ],
        ),
    ],
  );

  Widget _sourceTile(ZangetsuSource s, ZangetsuSource? installed) {
    final update = installed == null ? null : _store.updateFor(installed);
    final shown = installed ?? s;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            _icon(s.icon),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (s.nsfw) ...[
                        const SizedBox(width: 6),
                        const _Badge(text: '18+', color: AppColors.error),
                      ],
                    ],
                  ),
                  Text(
                    '${s.lang.toUpperCase()} · '
                    '${s.isAnime ? 'ext.type_anime'.tr() : 'zangetsu.type_movies'.tr()}'
                    ' · v${shown.version}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            ..._actions(s, installed, update),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(
    ZangetsuSource s,
    ZangetsuSource? installed,
    ZangetsuSource? update,
  ) {
    if (s.builtIn) {
      return [_Badge(text: 'zangetsu.built_in'.tr(), color: AppColors.success)];
    }
    if (installed == null) {
      return [
        TextButton(
          onPressed: _busy ? null : () => _install(s),
          child: Text('general.install'.tr()),
        ),
      ];
    }
    return [
      if (update != null)
        IconButton(
          tooltip: 'zangetsu.update_to'.tr(args: [update.version]),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.system_update_alt_rounded, color: _accent),
          onPressed: _busy ? null : () => _update(installed),
        ),
      Switch(
        value: installed.enabled,
        activeThumbColor: Colors.white,
        activeTrackColor: _accent,
        onChanged: _busy ? null : (v) => _toggle(installed, v),
      ),
      IconButton(
        tooltip: 'general.remove'.tr(),
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.delete_outline, color: AppColors.error),
        onPressed: _busy ? null : () => _remove(installed),
      ),
    ];
  }

  Widget _icon(String? url) {
    final fallback = Container(
      width: 26,
      height: 26,
      color: AppColors.surfaceVariant,
      child: const Icon(Icons.bolt_rounded, size: 14, color: AppColors.textHint),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: url == null || url.isEmpty
          ? fallback
          : Image.network(
              url,
              width: 26,
              height: 26,
              cacheWidth: 78,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
    ),
  );
}
