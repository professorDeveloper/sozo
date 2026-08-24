import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/extensions/domain/entities/extension_repo_entity.dart';
import 'package:soplay/features/extensions/presentation/widgets/recommended_repos_section.dart';
import 'package:soplay/features/cloudstream/presentation/pages/cloudstream_plugins_page.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';

class CloudStreamSourcesPage extends StatefulWidget {
  const CloudStreamSourcesPage({super.key});

  @override
  State<CloudStreamSourcesPage> createState() => _CloudStreamSourcesPageState();
}

class _CloudStreamSourcesPageState extends State<CloudStreamSourcesPage> {
  static const _icon =
      'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTRzeluIShlMnhgHeVHgTSkvsthvQEK2xaS5A&s';

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
    _progressSub = CloudStreamChannel.installProgress.listen((p) {
      if (!mounted || !_busy) return;
      setState(() {
        _status = p.total > 0
            ? 'Installing ${p.current} / ${p.total} plugins…'
            : 'Installing plugins…';
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
    final repos = await CloudStreamChannel.listRepos();
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

  Future<void> _add() => _browse(_controller.text);

  /// Open the repo's plugin list so the user installs only the plugins they
  /// want, instead of force-installing every provider in the repo.
  Future<void> _browse(String input) async {
    final url = input.trim();
    if (url.isEmpty || _busy) return;
    FocusScope.of(context).unfocus();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CloudStreamPluginsPage(repoUrl: url),
      ),
    );
    if (!mounted) return;
    _controller.clear();
    await _refresh();
    _reloadProviders();
  }

  Future<void> _remove(String url) async {
    await CloudStreamChannel.removeRepo(url);
    if (!mounted) return;
    _reloadProviders();
    await _refresh();
    if (!mounted) return;
    setState(() {
      _statusError = false;
      _status = 'Source removed.';
    });
  }

  Future<void> _checkUpdates() async {
    if (_busy || _repos.isEmpty) return;
    setState(() {
      _busy = true;
      _statusError = false;
      _status = 'Checking for updates…';
    });
    try {
      final res = await CloudStreamChannel.checkUpdates();
      final updated = (res['updated'] as List?) ?? const [];
      if (!mounted) return;
      if (updated.isNotEmpty) {
        _reloadProviders();
        await _refresh();
      }
      if (!mounted) return;
      setState(() {
        _statusError = false;
        _status = updated.isEmpty
            ? 'All extensions are up to date.'
            : 'Updated ${updated.length}: '
                '${updated.take(6).join(', ')}${updated.length > 6 ? '…' : ''}';
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

  @override
  Widget build(BuildContext context) {
    if (!CloudStreamChannel.isSupported) {
      return Scaffold(
        appBar: AppBar(title: const Text('CloudStream Sources')),
        body: const Center(
          child: Text('This feature is only available on Android'),
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
        title: const Text('CloudStream Sources'),
        actions: [
          PopupMenuButton<String>(
            enabled: !_busy && _repos.isNotEmpty,
            icon: const Icon(Icons.more_vert),
            color: AppColors.surface,
            onSelected: (v) {
              if (v == 'updates') _checkUpdates();
            },
            itemBuilder: (_) => const [
              PopupMenuItem<String>(
                value: 'updates',
                child: Row(
                  children: [
                    Icon(Icons.system_update_alt,
                        size: 18, color: Colors.white70),
                    SizedBox(width: 10),
                    Text('Check for updates',
                        style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
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
            kind: ExtensionRepoKind.cloudstream,
            installedUrls: {for (final r in _repos) (r['url'] ?? '').trim()},
            busy: _busy,
            accent: AppColors.primary,
            fallbackIcon: _icon,
            // CloudStream opens the repo's plugin list rather than installing
            // everything — a repo can carry 100+ providers.
            onInstall: (repo) => _browse(repo.url),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text('INSTALLED SOURCES',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textHint, letterSpacing: 1)),
              const Spacer(),
              if (_repos.isNotEmpty)
                Text('${_repos.length}',
                    style: const TextStyle(color: AppColors.textHint)),
            ],
          ),
          const SizedBox(height: 8),
          if (_repos.isEmpty)
            _empty()
          else
            ..._repos.map(_repoTile),
        ],
      ),
    );
  }

  Widget _header() => Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(_icon, width: 44, height: 44, fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    Icon(Icons.extension_outlined, color: AppColors.primary, size: 40)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Add a CloudStream repo, then install only the plugins you want — '
              'only those show up as providers. They run on your device '
              '(Android only).',
              style: TextStyle(color: AppColors.textHint, fontSize: 12.5, height: 1.35),
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
              style: const TextStyle(color: Colors.white),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Repo URL',
                hintText: 'https://…/repo.json',
                hintStyle: const TextStyle(color: AppColors.textHint),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
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
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed: _busy ? null : _add,
                icon: const Icon(Icons.travel_explore),
                label: const Text('Browse plugins'),
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
                style: TextStyle(color: color, fontSize: 12.5)),
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
        child: const Column(
          children: [
            Icon(Icons.cloud_off_outlined, color: AppColors.textHint, size: 32),
            SizedBox(height: 8),
            Text('No sources yet',
                style: TextStyle(color: AppColors.textHint)),
          ],
        ),
      );

  Widget _repoTile(Map<String, String> repo) {
    final url = repo['url'] ?? '';
    final name = repo['name'] ?? url;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(_icon, width: 34, height: 34, fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  Icon(Icons.extension_outlined, color: AppColors.primary)),
        ),
        title: Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(url,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          onPressed: _busy ? null : () => _remove(url),
        ),
        onTap: _busy ? null : () => _browse(url),
      ),
    );
  }
}
