import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/manga/manga_channel.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/extensions/domain/entities/extension_repo_entity.dart';
import 'package:soplay/features/extensions/presentation/widgets/recommended_repos_section.dart';
import 'package:soplay/features/manga/presentation/pages/manga_source_settings_page.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';

class MangaSourcesPage extends StatefulWidget {
  const MangaSourcesPage({super.key});

  @override
  State<MangaSourcesPage> createState() => _MangaSourcesPageState();
}

class _MangaSourcesPageState extends State<MangaSourcesPage> {
  static const String _logo =
      'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcShNP_m0078YcYRUbudCuZhohC2U143Re4MfQ&s';
  /// The manga screens used to carry their own private blue. There is one
  /// accent in the app now, and the user chooses it.
  static Color get _accent => AppColors.primary;

  late final HiveService _hive = getIt<HiveService>();

  final _controller = TextEditingController();
  List<Map<String, String>> _repos = const [];
  List<Map<String, dynamic>> _sources = const [];
  bool _busy = false;
  String? _status;
  bool _statusError = false;
  StreamSubscription<({int current, int total})>? _progressSub;

  @override
  void initState() {
    super.initState();
    _refresh();
    _progressSub = MangaChannel.installProgress.listen((p) {
      if (!mounted || !_busy) return;
      setState(() {
        _status = p.total > 0
            ? 'manga.installing_progress'
                .tr(args: ['${p.current}', '${p.total}'])
            : 'manga.installing'.tr();
        _statusError = false;
      });
    });
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final repos = await MangaChannel.listRepos();
    final sources = await MangaChannel.listProviders();
    if (!mounted) return;
    setState(() {
      _repos = repos.map((e) {
        final m = (e is Map) ? e : const {};
        final url = (m['url'] ?? e).toString();
        final name = (m['name'] ?? '').toString();
        return {'url': url, 'name': name.isNotEmpty ? name : url};
      }).toList();
      _sources = sources
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    });
  }

  void _openSourceSettings(Map<String, dynamic> source) {
    final id = (source['id'] as String? ?? '');
    final bareId = id.startsWith('mn:') ? id.substring(3) : id;
    final name = (source['name'] as String?) ?? bareId;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            MangaSourceSettingsPage(sourceId: bareId, name: name),
      ),
    );
  }

  void _reloadProviders() {
    try {
      context.read<ProviderBloc>().add(const ProviderLoad());
    } catch (_) {}
  }

  /// Installed sources minus the adult ones while the opt-in is off.
  List<Map<String, dynamic>> get _visibleSources => _hive.showNsfwMangaSources
      ? _sources
      : _sources.where((s) => s['nsfw'] != true).toList();

  Future<void> _setShowNsfw(bool value) async {
    await _hive.setShowNsfwMangaSources(value);
    if (!mounted) return;
    setState(() {});
    // The provider picker builds its manga entries from the same plugin list,
    // so it has to be rebuilt too. Reloading also settles the awkward case of
    // switching the setting off while an 18+ source is the active provider:
    // ProviderBloc drops it from the list and its resolver moves the selection
    // to a visible provider and persists it, rather than leaving the app
    // pointed at a source the user just asked to stop seeing.
    _reloadProviders();
  }

  Future<void> _add() => _install(_controller.text.trim());

  Future<void> _install(String input) async {
    if (input.isEmpty || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _statusError = false;
      _status = 'manga.installing_long'.tr();
    });
    try {
      final res = await MangaChannel.addRepo(input);
      final count = res['sourceCount'] ?? 0;
      final providers = (res['providers'] as List?)?.length ?? 0;
      if (!mounted) return;
      if (count > 0) {
        _controller.clear();
        _reloadProviders();
      }
      await _refresh();
      if (!mounted) return;
      setState(() {
        _statusError = count == 0;
        _status = count == 0
            ? 'manga.no_extensions'.tr()
            : 'manga.added_sources'.tr(args: ['$count', '$providers']);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusError = true;
        _status = 'manga.error_prefix'.tr(args: ['$e']);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Re-checks every installed repo for newer extension versions and applies
  /// them — the manga counterpart of the CloudStream page's update action. The
  /// native side swaps the stored metadata and drops the stale apk, so the new
  /// one is fetched lazily on next use.
  Future<void> _checkUpdates() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _statusError = false;
      _status = 'manga.checking_updates'.tr();
    });
    try {
      final res = await MangaChannel.checkUpdates();
      final count = (res['count'] as num?)?.toInt() ?? 0;
      if (!mounted) return;
      if (count > 0) _reloadProviders();
      setState(() {
        _statusError = false;
        _status = count == 0
            ? 'manga.up_to_date'.tr()
            : 'manga.updated_n'.tr(args: ['$count']);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusError = true;
        _status = 'Error: $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String url) async {
    await MangaChannel.removeRepo(url);
    if (!mounted) return;
    _reloadProviders();
    await _refresh();
    if (!mounted) return;
    setState(() {
      _statusError = false;
      _status = 'manga.source_removed'.tr();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!MangaChannel.isSupported) {
      return Scaffold(
        appBar: AppBar(title: Text('manga.sources_title'.tr())),
        body: Center(
          child: Text('manga.android_only'.tr()),
        ),
      );
    }
    final visibleSources = _visibleSources;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Text('manga.sources_title'.tr()),
        actions: [
          IconButton(
            tooltip: 'manga.check_updates'.tr(),
            icon: const Icon(Icons.system_update_alt_rounded),
            onPressed: (_busy || _repos.isEmpty) ? null : _checkUpdates,
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
            kind: ExtensionRepoKind.manga,
            installedUrls: {for (final r in _repos) (r['url'] ?? '').trim()},
            busy: _busy,
            accent: _accent,
            fallbackIcon: _logo,
            nsfwAllowed: _hive.showNsfwMangaSources,
            title: 'manga.recommended'.tr(),
            onInstall: (repo) => _install(repo.url),
          ),
          const SizedBox(height: 24),
          _nsfwCard(),
          const SizedBox(height: 24),
          Row(
            children: [
              Text('manga.installed_sources'.tr(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textHint, letterSpacing: 1)),
              const Spacer(),
              if (_repos.isNotEmpty)
                Text('${_repos.length}',
                    style: const TextStyle(color: AppColors.textHint)),
            ],
          ),
          const SizedBox(height: 8),
          if (_repos.isEmpty) _empty() else ..._repos.map(_repoTile),
          if (visibleSources.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Icon(Icons.tune, size: 15, color: _accent),
                const SizedBox(width: 6),
                Text('manga.source_settings'.tr(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textHint, letterSpacing: 1)),
              ],
            ),
            const SizedBox(height: 8),
            ...visibleSources.map(_sourceTile),
          ],
        ],
      ),
    );
  }

  Widget _nsfwCard() => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 0.6),
        ),
        padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 6, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text('manga.show_nsfw'.tr(),
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 6),
                      const _NsfwChip(),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text('manga.show_nsfw_hint'.tr(),
                      style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 12,
                          height: 1.35)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Switch.adaptive(
              value: _hive.showNsfwMangaSources,
              activeThumbColor: _accent,
              onChanged: _setShowNsfw,
            ),
          ],
        ),
      );

  Widget _sourceTile(Map<String, dynamic> source) {
    final name = (source['name'] as String?) ?? '';
    final lang = (source['lang'] as String?) ?? '';
    final nsfw = source['nsfw'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: _logoBox(34),
          title: Row(
            children: [
              Flexible(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
              if (nsfw) ...[
                const SizedBox(width: 6),
                const _NsfwChip(),
              ],
            ],
          ),
          subtitle: lang.isNotEmpty
              ? Text(lang.toUpperCase(),
                  style: const TextStyle(
                      color: AppColors.textHint, fontSize: 11))
              : null,
          trailing: const Icon(Icons.settings_outlined,
              color: AppColors.textHint),
          onTap: () => _openSourceSettings(source),
        ),
      ),
    );
  }

  Widget _logoBox(double size, {double radius = 9}) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.network(
          _logo,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            width: size,
            height: size,
            color: Colors.white10,
            child: Icon(Icons.menu_book_outlined,
                color: Colors.white54, size: size * 0.55),
          ),
        ),
      );

  Widget _header() => Row(
        children: [
          _logoBox(44, radius: 11),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'manga.sources_desc'.tr(),
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
                labelText: 'manga.repo_url'.tr(),
                labelStyle: const TextStyle(color: AppColors.textHint),
                floatingLabelStyle: TextStyle(color: _accent),
                hintText: 'https://…/index.min.json',
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
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, color: AppColors.textHint),
                        tooltip: 'Clear',
                        onPressed: _busy
                            ? null
                            : () => setState(() => _controller.clear()),
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
                label: Text(_busy ? 'manga.installing'.tr() : 'manga.add_source'.tr()),
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
            child:
                Text(_status!, style: TextStyle(color: color, fontSize: 12.5)),
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
            Text('manga.no_sources'.tr(),
                style: const TextStyle(color: AppColors.textHint)),
          ],
        ),
      );

  Widget _repoTile(Map<String, String> repo) {
    final url = repo['url'] ?? '';
    final name = repo['name'] ?? url;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: _logoBox(34),
          title: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          subtitle: Text(url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: _busy ? null : () => _remove(url),
          ),
        ),
      ),
    );
  }
}

/// The only signal that a source is adult, so it stays on every source tile
/// even when the user has opted in to seeing them.
class _NsfwChip extends StatelessWidget {
  const _NsfwChip();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFE53935).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text('18+',
            style: TextStyle(
                color: Color(0xFFE53935),
                fontSize: 9,
                fontWeight: FontWeight.w700)),
      );
}
