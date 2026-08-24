import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';

/// Browse a single CloudStream repo and install only the plugins you want.
///
/// Adding a repo no longer force-installs every provider — the user toggles each
/// plugin here, and only installed plugins become providers.
class CloudStreamPluginsPage extends StatefulWidget {
  const CloudStreamPluginsPage({
    super.key,
    required this.repoUrl,
    this.repoName,
  });

  final String repoUrl;
  final String? repoName;

  @override
  State<CloudStreamPluginsPage> createState() => _CloudStreamPluginsPageState();
}

class _CloudStreamPluginsPageState extends State<CloudStreamPluginsPage> {
  bool _loading = true;
  bool _installingAll = false;
  int _installAllDone = 0;
  int _installAllTotal = 0;
  String? _currentInstalling;
  String? _error;
  String _repoName = '';
  List<Map<String, dynamic>> _plugins = const [];
  final Set<String> _busy = <String>{};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _repoName = widget.repoName ?? widget.repoUrl;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await CloudStreamChannel.listRepoPlugins(widget.repoUrl);
      final plugins = (res['plugins'] as List?) ?? const [];
      if (!mounted) return;
      final name = (res['name'] as String?)?.trim() ?? '';
      setState(() {
        if (name.isNotEmpty) _repoName = name;
        _plugins = plugins
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _reloadProviders() {
    try {
      context.read<ProviderBloc>().add(const ProviderLoad());
    } catch (_) {}
  }

  Future<void> _toggle(Map<String, dynamic> p) async {
    final name = (p['internalName'] as String?) ?? '';
    if (name.isEmpty || _busy.contains(name) || _installingAll) return;
    final installed = p['installed'] == true;
    setState(() => _busy.add(name));
    try {
      if (installed) {
        await CloudStreamChannel.uninstallPlugin(widget.repoUrl, name);
      } else {
        final res = await CloudStreamChannel.installPlugin(widget.repoUrl, name);
        if (((res['pluginCount'] as num?)?.toInt() ?? 0) == 0) {
          throw Exception('install failed');
        }
      }
      if (!mounted) return;
      setState(() => p['installed'] = !installed);
      _reloadProviders();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            installed ? 'Could not remove plugin' : 'Could not install plugin',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(name));
    }
  }

  /// Install every not-yet-installed plugin ONE BY ONE, flipping each row to
  /// "installed" as it completes and naming the current one — so the user sees
  /// exactly what's happening instead of a frozen-looking spinner.
  Future<void> _installAll() async {
    if (_installingAll) return;
    final pending =
        _plugins.where((p) => p['installed'] != true).toList();
    if (pending.isEmpty) return;
    setState(() {
      _installingAll = true;
      _installAllTotal = pending.length;
      _installAllDone = 0;
      _currentInstalling = null;
    });
    for (final p in pending) {
      if (!mounted) return;
      final name = (p['internalName'] as String?) ?? '';
      if (name.isEmpty) {
        setState(() => _installAllDone++);
        continue;
      }
      setState(() => _currentInstalling = (p['name'] as String?) ?? name);
      try {
        final res =
            await CloudStreamChannel.installPlugin(widget.repoUrl, name);
        if (!mounted) return;
        if (((res['pluginCount'] as num?)?.toInt() ?? 0) > 0) {
          setState(() => p['installed'] = true);
          _reloadProviders();
        }
      } catch (_) {
        // skip this plugin, keep going
      }
      if (!mounted) return;
      setState(() => _installAllDone++);
    }
    if (mounted) {
      setState(() {
        _installingAll = false;
        _currentInstalling = null;
      });
    }
  }

  int get _installedCount =>
      _plugins.where((p) => p['installed'] == true).length;

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _plugins;
    return _plugins.where((p) {
      final name = ((p['name'] as String?) ?? '').toLowerCase();
      final internal = ((p['internalName'] as String?) ?? '').toLowerCase();
      final lang = ((p['language'] as String?) ?? '').toLowerCase();
      return name.contains(q) || internal.contains(q) || lang.contains(q);
    }).toList();
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _repoName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            if (!_loading && _error == null)
              Text(
                '${_plugins.length} plugins · $_installedCount installed',
                style: const TextStyle(fontSize: 11, color: AppColors.textHint),
              ),
          ],
        ),
        actions: [
          if (!_loading && _error == null && _plugins.isNotEmpty)
            TextButton(
              onPressed: _installingAll ? null : _installAll,
              child: _installingAll
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Install all'),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: AppColors.textHint, size: 36),
              const SizedBox(height: 10),
              Text(
                'Could not load this repo.\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textHint),
              ),
              const SizedBox(height: 14),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_plugins.isEmpty) {
      return const Center(
        child: Text(
          'No plugins found in this repo',
          style: TextStyle(color: AppColors.textHint),
        ),
      );
    }
    final items = _filtered;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            style: const TextStyle(color: Colors.white),
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search plugins…',
              hintStyle: const TextStyle(color: AppColors.textHint),
              prefixIcon: const Icon(Icons.search,
                  color: AppColors.textHint, size: 20),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        if (_installingAll) _installBanner(),
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Text('No matches',
                      style: TextStyle(color: AppColors.textHint)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _pluginTile(items[i]),
                ),
        ),
      ],
    );
  }

  Widget _installBanner() {
    final total = _installAllTotal;
    final done = _installAllDone;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Installing $done / $total'
                  '${_currentInstalling != null ? ' · $_currentInstalling' : ''}',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppColors.primary, fontSize: 12.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total > 0 ? done / total : null,
              minHeight: 4,
              backgroundColor: Colors.white12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pluginTile(Map<String, dynamic> p) {
    final name =
        (p['name'] as String?) ?? (p['internalName'] as String?) ?? '';
    final lang = ((p['language'] as String?) ?? '').toUpperCase();
    final tvTypes =
        (p['tvTypes'] as List?)?.whereType<String>().toList() ?? const [];
    final internalName = (p['internalName'] as String?) ?? '';
    final installed = p['installed'] == true;
    final busy = _busy.contains(internalName);
    final subtitle = [
      if (lang.isNotEmpty) lang,
      ...tvTypes.take(3),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: _icon(p['iconUrl'] as String?),
          title: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600),
          ),
          subtitle: subtitle.isEmpty
              ? null
              : Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: AppColors.textHint, fontSize: 11),
                ),
          trailing: SizedBox(
            width: 40,
            height: 40,
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(9),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    onPressed: () => _toggle(p),
                    tooltip: installed ? 'Remove' : 'Install',
                    icon: Icon(
                      installed
                          ? Icons.check_circle
                          : Icons.add_circle_outline,
                      color: installed ? Colors.green : AppColors.primary,
                    ),
                  ),
          ),
          onTap: busy ? null : () => _toggle(p),
        ),
      ),
    );
  }

  Widget _icon(String? url) {
    Widget fallback() => Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.extension_rounded,
              color: AppColors.primary, size: 18),
        );
    if (url == null || url.isEmpty) return fallback();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 34,
        height: 34,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback(),
      ),
    );
  }
}
