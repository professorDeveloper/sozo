import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/app_buttons.dart';
import 'package:soplay/features/jellyfin/data/jellyfin_api.dart';
import 'package:soplay/features/jellyfin/data/jellyfin_bridge.dart';
import 'package:soplay/features/jellyfin/data/jellyfin_server_store.dart';
import 'package:soplay/features/jellyfin/domain/jellyfin_server.dart';
import 'package:soplay/features/jellyfin/presentation/pages/jellyfin_connect_page.dart';
import 'package:soplay/features/jellyfin/presentation/widgets/jellyfin_widgets.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';
import 'package:soplay/features/profile/presentation/widgets/settings_tiles.dart';

/// The Jellyfin servers this device is signed in to.
class JellyfinServersPage extends StatelessWidget {
  const JellyfinServersPage({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const JellyfinServersPage()));

  JellyfinServerStore get _store => getIt<JellyfinServerStore>();

  Future<void> _connect(BuildContext context, {JellyfinServer? server}) async {
    final saved = await JellyfinConnectPage.open(context, server: server);
    if (saved == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('jellyfin.saved'.tr(namedArgs: {'name': saved.name})),
        action: SnackBarAction(
          label: 'jellyfin.use_now'.tr(),
          onPressed: () => context.read<ProviderBloc>().add(
            ProviderSelect(saved.providerId),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _store.revision,
      builder: (context, _, _) {
        final servers = _store.servers()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        return SettingsPageScaffold(
          title: 'jellyfin.title'.tr(),
          children: [
            if (servers.isEmpty)
              _EmptyServers(onConnect: () => _connect(context))
            else ...[
              SettingsLabel('jellyfin.servers_label'.tr()),
              SettingsCard(
                children: [
                  for (var i = 0; i < servers.length; i++) ...[
                    if (i > 0) const SettingsDivider(),
                    _ServerRow(
                      server: servers[i],
                      onSignIn: () => _connect(context, server: servers[i]),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 18),
              AppSecondaryButton(
                label: 'jellyfin.connect'.tr(),
                icon: Icons.add_rounded,
                onPressed: () => _connect(context),
              ),
            ],
            SettingsFootnote('jellyfin.servers_footnote'.tr()),
          ],
        );
      },
    );
  }
}

class _EmptyServers extends StatelessWidget {
  const _EmptyServers({required this.onConnect});

  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 36, 8, 20),
      child: Column(
        children: [
          const JellyfinLogo(size: 64),
          const SizedBox(height: 18),
          Text(
            'jellyfin.empty_title'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'jellyfin.empty_body'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 22),
          AppPrimaryButton(
            label: 'jellyfin.connect'.tr(),
            icon: Icons.add_rounded,
            onPressed: onConnect,
          ),
        ],
      ),
    );
  }
}

enum _Probe { idle, checking, ok, failed }

class _ServerRow extends StatefulWidget {
  const _ServerRow({required this.server, required this.onSignIn});

  final JellyfinServer server;
  final VoidCallback onSignIn;

  @override
  State<_ServerRow> createState() => _ServerRowState();
}

class _ServerRowState extends State<_ServerRow> {
  _Probe _probe = _Probe.idle;
  String _detail = '';

  JellyfinServer get _server => widget.server;

  /// Reachable is not enough: the saved session has to still be accepted,
  /// which is what an authenticated call proves.
  Future<void> _test() async {
    setState(() => _probe = _Probe.checking);
    final watch = Stopwatch()..start();
    try {
      await getIt<JellyfinApi>().views(_server);
      if (!mounted) return;
      setState(() {
        _probe = _Probe.ok;
        _detail = 'jellyfin.test_ok'.tr(
          namedArgs: {'ms': '${watch.elapsedMilliseconds}'},
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _probe = _Probe.failed;
        _detail = jellyfinErrorText(e);
      });
    }
  }

  Future<void> _libraries() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _LibrariesPage(serverId: _server.id),
    ),
  );

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('jellyfin.remove'.tr()),
        content: Text(
          'jellyfin.remove_confirm'.tr(namedArgs: {'name': _server.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text('general.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(
              'general.remove'.tr(),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // Read now: removing the server rebuilds the list without this row.
    final providers = context.read<ProviderBloc>();
    // Best effort: the session is revoked on the server when it answers, and
    // forgotten here either way.
    unawaited(getIt<JellyfinApi>().logout(_server).catchError((Object _) {}));
    await getIt<JellyfinServerStore>().remove(_server.id);
    providers.add(const ProviderLoad(localOnly: true));
  }

  @override
  Widget build(BuildContext context) {
    final status = switch (_probe) {
      _Probe.idle => null,
      _Probe.checking => 'jellyfin.testing'.tr(),
      _ => _detail,
    };
    final statusColor = switch (_probe) {
      _Probe.ok => AppColors.success,
      _Probe.failed => AppColors.errorLight,
      _ => AppColors.textHint,
    };
    return InkWell(
      onTap: _libraries,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
        child: Row(
          children: [
            const JellyfinLogo(size: 36),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _server.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_server.userName} · ${_server.host}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 12.5,
                    ),
                  ),
                  if (status != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (_probe == _Probe.checking)
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(strokeWidth: 1.6),
                          )
                        else
                          Icon(
                            _probe == _Probe.ok
                                ? Icons.check_circle_rounded
                                : Icons.error_outline_rounded,
                            size: 13,
                            color: statusColor,
                          ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            status,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: statusColor, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(
                Icons.more_vert_rounded,
                color: AppColors.textSecondary,
              ),
              color: AppColors.surface,
              onSelected: (v) => switch (v) {
                'test' => _test(),
                'libraries' => _libraries(),
                'signin' => Future.sync(widget.onSignIn),
                _ => _remove(),
              },
              itemBuilder: (_) => [
                _item(
                  'test',
                  Icons.network_check_rounded,
                  'jellyfin.test_connection',
                ),
                _item(
                  'libraries',
                  Icons.video_library_outlined,
                  'jellyfin.libraries_title',
                ),
                _item('signin', Icons.login_rounded, 'jellyfin.sign_in_again'),
                _item(
                  'remove',
                  Icons.delete_outline_rounded,
                  'jellyfin.remove',
                  destructive: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _item(
    String value,
    IconData icon,
    String key, {
    bool destructive = false,
  }) {
    final color = destructive ? AppColors.error : AppColors.textPrimary;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 12),
          Text(key.tr(), style: TextStyle(color: color)),
        ],
      ),
    );
  }
}

/// Which libraries get a row on Home, for a server already signed in.
class _LibrariesPage extends StatefulWidget {
  const _LibrariesPage({required this.serverId});

  final String serverId;

  @override
  State<_LibrariesPage> createState() => _LibrariesPageState();
}

class _LibrariesPageState extends State<_LibrariesPage> {
  late Future<List<Map<String, dynamic>>> _load = _fetch();
  late final ProviderBloc _providers = context.read<ProviderBloc>();
  final Set<String> _hidden = {};
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _providers;
  }

  JellyfinServer? get _server =>
      getIt<JellyfinServerStore>().byId(widget.serverId);

  Future<List<Map<String, dynamic>>> _fetch() async {
    final server = _server;
    if (server == null) return const [];
    _hidden
      ..clear()
      ..addAll(server.hiddenLibraries);
    final views = await getIt<JellyfinApi>().views(server);
    return [
      for (final v in views)
        if (JellyfinBridge.playableCollections.contains(
              v['CollectionType']?.toString(),
            ) &&
            v['Id'] != null)
          v,
    ];
  }

  Future<void> _toggle(String id, bool visible) async {
    final server = _server;
    if (server == null) return;
    setState(() => visible ? _hidden.remove(id) : _hidden.add(id));
    _dirty = true;
    await getIt<JellyfinServerStore>().save(
      server.copyWith(hiddenLibraries: _hidden.toList()),
    );
  }

  @override
  void dispose() {
    // Home rebuilds its rows from the provider list, so a changed selection
    // shows up the next time it loads rather than needing a restart.
    if (_dirty) _providers.add(const ProviderLoad(localOnly: true));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: 'jellyfin.libraries_title'.tr(),
      children: [
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _load,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    const Icon(
                      Icons.cloud_off_rounded,
                      size: 40,
                      color: AppColors.textHint,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      jellyfinErrorText(snap.error!),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppSecondaryButton(
                      label: 'general.retry'.tr(),
                      icon: Icons.refresh_rounded,
                      expand: false,
                      onPressed: () => setState(() => _load = _fetch()),
                    ),
                  ],
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsLabel('jellyfin.libraries_label'.tr()),
                JellyfinLibraryToggles(
                  libraries: snap.data ?? const [],
                  hidden: _hidden,
                  onChanged: _toggle,
                ),
                SettingsFootnote('jellyfin.libraries_intro'.tr()),
              ],
            );
          },
        ),
      ],
    );
  }
}
