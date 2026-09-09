part of 'profile_page.dart';

/// The desktop panels: providers, activity, connections, security, extensions.
/// Mobile builds its hub from `profile_page.hub.dart` instead.
class _ProvidersSection extends StatelessWidget {
  const _ProvidersSection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsLabel('profile.section_providers'.tr()),
          const SettingsCard(children: [ProviderTile()]),
        ],
      ),
    );
  }
}

void openProviderPicker(BuildContext context, ProviderBloc bloc) {
  ProvidersPage.open(context, bloc);
}

class _WatchHistorySection extends StatefulWidget {
  const _WatchHistorySection();

  @override
  State<_WatchHistorySection> createState() => _WatchHistorySectionState();
}

class _WatchHistorySectionState extends State<_WatchHistorySection> {
  final HistoryService _historyService = getIt<HistoryService>();
  final GetDownloadsUseCase _downloadService = getIt<GetDownloadsUseCase>();
  int _historyCount = 0;
  int _downloadCount = 0;

  @override
  void initState() {
    super.initState();
    _historyService.revision.addListener(_reload);
    _downloadService.revision.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _historyService.revision.removeListener(_reload);
    _downloadService.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _historyCount = _historyService.getAll().length;
      _downloadCount = _downloadService().length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsLabel(
            'profile.section_library'.tr(),
            featureIds: const ['stats'],
          ),
          SettingsCard(
            children: [
              SettingsNavTile(
                icon: Icons.history_rounded,
                title: 'profile.watch_history'.tr(),
                value: _historyCount > 0 ? '$_historyCount' : null,
                onTap: () => context.push('/history'),
              ),
              const SettingsDivider(),
              SettingsNavTile(
                icon: Icons.download_rounded,
                title: 'profile.downloads'.tr(),
                value: _downloadCount > 0 ? '$_downloadCount' : null,
                onTap: () => context.push('/downloads'),
              ),
              const SettingsDivider(),
              SettingsNavTile(
                icon: Icons.notifications_active_outlined,
                title: 'tracker.title'.tr(),
                onTap: () => context.push('/following'),
              ),
              const SettingsDivider(),
              SettingsNavTile(
                icon: Icons.bar_chart_rounded,
                title: 'stats.title'.tr(),
                subtitle: 'stats.entry_subtitle'.tr(),
                featureId: 'stats',
                onTap: () => WatchStatsPage.open(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Sits directly under the streak card: the offer to connect a tracker only
/// works if it is seen.
class _ConnectionsSection extends StatelessWidget {
  const _ConnectionsSection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsLabel(
            'profile.section_connections'.tr(),
            featureIds: const ['backup'],
          ),
          SettingsCard(
            children: [
              const _ConnectionsTile(),
              const SettingsDivider(),
              SettingsNavTile(
                icon: Icons.cast_connected_rounded,
                title: 'link_tv.title'.tr(),
                subtitle: 'link_tv.tile_subtitle'.tr(),
                onTap: () => context.push('/link-tv'),
              ),
              const SettingsDivider(),
              SettingsNavTile(
                icon: Icons.devices_rounded,
                title: BridgeControl.canHost
                    ? 'profile.share_sources_desktop'.tr()
                    : Platform.isIOS
                    ? 'ios.sources_title'.tr()
                    : 'profile.desktop_sources'.tr(),
                onTap: () => context.push('/desktop-share'),
              ),
              const SettingsDivider(),
              SettingsNavTile(
                icon: Icons.backup_outlined,
                title: 'backup.title'.tr(),
                featureId: 'backup',
                onTap: () => context.push('/backup'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The Connections row, which shows both trackers' state inline: whether a
/// tracker is connected is the entire question a user opens this row to
/// answer. Listens to both services so connecting elsewhere updates it.
class _ConnectionsTile extends StatefulWidget {
  const _ConnectionsTile();

  @override
  State<_ConnectionsTile> createState() => _ConnectionsTileState();
}

class _ConnectionsTileState extends State<_ConnectionsTile> {
  final AnilistService _anilist = getIt<AnilistService>();
  final MalService _mal = getIt<MalService>();

  @override
  void initState() {
    super.initState();
    _anilist.addListener(_onChange);
    _mal.addListener(_onChange);
  }

  @override
  void dispose() {
    _anilist.removeListener(_onChange);
    _mal.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  /// Account names rather than service names: the logos beside this already
  /// say which services. Falls back to the service name when a link carries
  /// no username yet.
  String _subtitle() {
    final names = <String>[
      if (_anilist.isConnected)
        (_anilist.viewer?.name.trim().isNotEmpty ?? false)
            ? _anilist.viewer!.name.trim()
            : 'AniList',
      if (_mal.isConnected)
        (_mal.viewer?.name.trim().isNotEmpty ?? false)
            ? _mal.viewer!.name.trim()
            : 'MyAnimeList',
    ];
    return names.isEmpty ? 'anilist.connect_tagline'.tr() : names.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final anyConnected = _anilist.isConnected || _mal.isConnected;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/connections'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
          child: Row(
            children: [
              _TrackerMark(
                connected: _anilist.isConnected,
                child: const AnilistLogo(size: 28, radius: 8),
              ),
              const SizedBox(width: 7),
              _TrackerMark(
                connected: _mal.isConnected,
                child: const MalLogo(size: 28, radius: 8),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'anilist.connections_title'.tr(),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: anyConnected ? kAnilistBlue : AppColors.textHint,
                        fontSize: 12.5,
                        fontWeight:
                            anyConnected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              if (!anyConnected)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: kAnilistBlue.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'anilist.connect_short'.tr(),
                    style: const TextStyle(
                      color: kAnilistBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                const SettingsChevron(),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tracker logo, dimmed while that tracker is not connected.
class _TrackerMark extends StatelessWidget {
  const _TrackerMark({required this.connected, required this.child});

  final bool connected;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Opacity(opacity: connected ? 1 : 0.38, child: child);
}

class _SecuritySection extends StatelessWidget {
  const _SecuritySection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsLabel('app_lock.section_label'.tr()),
          const SettingsCard(children: [_SecurityRows()]),
        ],
      ),
    );
  }
}

/// App lock + private list, as two bare rows.
class _SecurityRows extends StatefulWidget {
  const _SecurityRows();

  @override
  State<_SecurityRows> createState() => _SecurityRowsState();
}

class _SecurityRowsState extends State<_SecurityRows> {
  late final AppLockRepository _lock = getIt<AppLockRepository>();

  @override
  Widget build(BuildContext context) {
    final enabled = _lock.isEnabled;
    return Column(
      children: [
        SettingsNavTile(
          icon: Icons.lock_rounded,
          title: 'app_lock.app_lock'.tr(),
          value: enabled ? 'app_lock.state_on'.tr() : 'app_lock.state_off'.tr(),
          valueColor: enabled ? AppColors.primary : null,
          onTap: () async {
            await context.push('/app-lock-settings');
            if (mounted) setState(() {});
          },
        ),
        const SettingsDivider(),
        SettingsNavTile(
          icon: Icons.folder_special_rounded,
          title: 'app_lock.private_list'.tr(),
          onTap: () async {
            final unlocked = await requestPrivateUnlock(context);
            if (unlocked && context.mounted) {
              context.push('/private-list');
            }
          },
        ),
      ],
    );
  }
}

/// The installable-extension entries in one card. Which exist depends on the
/// platform; the card disappears entirely when nothing is supported.
class _ExtensionSourcesSection extends StatelessWidget {
  const _ExtensionSourcesSection();

  @override
  Widget build(BuildContext context) {
    final rows = SourcesPage.extensionRows(context);
    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsLabel('profile.section_extensions'.tr()),
          SettingsCard(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const SettingsDivider(),
                rows[i],
              ],
            ],
          ),
        ],
      ),
    );
  }
}
