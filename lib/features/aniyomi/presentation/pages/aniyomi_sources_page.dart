import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/extensions/domain/entities/extension_repo_entity.dart';
import 'package:soplay/features/extensions/presentation/widgets/recommended_repos_section.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';

class AniyomiSourcesPage extends StatefulWidget {
  const AniyomiSourcesPage({super.key});

  @override
  State<AniyomiSourcesPage> createState() => _AniyomiSourcesPageState();
}

class _AniyomiSourcesPageState extends State<AniyomiSourcesPage> {
  static const String _logo =
      'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcShNP_m0078YcYRUbudCuZhohC2U143Re4MfQ&s';
  static const Color _accent = Color(0xFF5B8DEF);

  final _controller = TextEditingController();
  List<Map<String, String>> _repos = const [];
  bool _busy = false;
  String? _status;
  bool _statusError = false;
  StreamSubscription<({int current, int total})>? _progressSub;

  @override
  void initState() {
    super.initState();
    _refresh();
    _progressSub = AniyomiChannel.installProgress.listen((p) {
      if (!mounted || !_busy) return;
      setState(() {
        _status = p.total > 0
            ? 'ext.installing_extensions_progress'
                .tr(args: ['${p.current}', '${p.total}'])
            : 'ext.installing_extensions'.tr();
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
    final repos = await AniyomiChannel.listRepos();
    if (!mounted) return;
    setState(() => _repos = repos.map((e) {
          final m = (e is Map) ? e : const {};
          final url = (m['url'] ?? e).toString();
          final name = (m['name'] ?? '').toString();
          return {'url': url, 'name': name.isNotEmpty ? name : url};
        }).toList());
  }

  void _reloadProviders() {
    try {
      context.read<ProviderBloc>().add(const ProviderLoad());
    } catch (_) {}
  }

  Future<void> _add() => _install(_controller.text.trim());

  Future<void> _install(String input) async {
    if (input.isEmpty || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _statusError = false;
      _status = 'ext.installing_long'.tr();
    });
    try {
      final res = await AniyomiChannel.addRepo(input);
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
            ? 'ext.none_found'.tr()
            : 'ext.added_sources_providers'
                .tr(args: ['$count', '$providers']);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusError = true;
        _status = 'ext.error'.tr(args: ['$e']);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Re-checks every installed repo for newer extension versions and applies
  /// them. Same contract as the CloudStream page's update action: the native
  /// side swaps the metadata and drops the stale apk, so the new one is fetched
  /// lazily on next use.
  Future<void> _checkUpdates() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _statusError = false;
      _status = 'ext.checking_extension_updates'.tr();
    });
    try {
      final res = await AniyomiChannel.checkUpdates();
      final count = (res['count'] as num?)?.toInt() ?? 0;
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

  Future<void> _remove(String url) async {
    await AniyomiChannel.removeRepo(url);
    if (!mounted) return;
    _reloadProviders();
    await _refresh();
    if (!mounted) return;
    setState(() {
      _statusError = false;
      _status = 'ext.source_removed'.tr();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!AniyomiChannel.isSupported) {
      return Scaffold(
        appBar: AppBar(title: Text('ext.aniyomi_title'.tr())),
        body: Center(
          child: Text('ext.android_only'.tr()),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Text('ext.aniyomi_title'.tr()),
        actions: [
          IconButton(
            tooltip: 'ext.check_extension_updates'.tr(),
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
            kind: ExtensionRepoKind.aniyomi,
            installedUrls: {for (final r in _repos) (r['url'] ?? '').trim()},
            busy: _busy,
            accent: _accent,
            fallbackIcon: _logo,
            onInstall: (repo) => _install(repo.url),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text('ext.installed_sources'.tr(),
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
        ],
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
            child: Icon(Icons.play_circle_outline,
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
              'ext.aniyomi_desc'.tr(),
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
                labelText: 'ext.repo_url'.tr(),
                labelStyle: const TextStyle(color: AppColors.textHint),
                floatingLabelStyle: const TextStyle(color: _accent),
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
                        tooltip: 'general.clear'.tr(),
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
                label: Text(_busy ? 'ext.installing'.tr() : 'ext.add_source'.tr()),
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
            Text('ext.no_sources_yet'.tr(),
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
