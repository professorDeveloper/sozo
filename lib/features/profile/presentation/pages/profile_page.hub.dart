part of 'profile_page.dart';

/// Mobile: the profile as a hub. Identity and numbers at the top, then one
/// row per area, each opening its own screen.
class _StatsStrip extends StatefulWidget {
  const _StatsStrip();

  @override
  State<_StatsStrip> createState() => _StatsStripState();
}

class _StatsStripState extends State<_StatsStrip> {
  final HistoryService _history = getIt<HistoryService>();
  final WatchStatsStore _stats = WatchStatsStore();

  @override
  void initState() {
    super.initState();
    // The stats store has no notifier of its own; history moving is the
    // signal that something was watched.
    _history.revision.addListener(_onChange);
  }

  @override
  void dispose() {
    _history.revision.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  /// True once anything at all has been watched on this device.
  ///
  /// Signed out, three zeroes under the sign-in card are noise; but the
  /// counters are local, so a guest who has actually watched something has
  /// numbers worth showing — and seeing them is half the argument for making
  /// an account to keep them.
  static bool get hasNumbers => WatchStatsStore().totalSeconds > 0;

  @override
  Widget build(BuildContext context) {
    final hours = _stats.totalSeconds ~/ 3600;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _StatTile(
            icon: Icons.schedule_rounded,
            value: '$hours',
            label: 'profile.stat_hours'.tr(),
            onTap: () => WatchStatsPage.open(context),
          ),
          const SizedBox(width: 10),
          _StatTile(
            icon: Icons.task_alt_rounded,
            value: '${_stats.completed}',
            label: 'profile.stat_completed'.tr(),
            onTap: () => WatchStatsPage.open(context),
          ),
          const SizedBox(width: 10),
          // Days with any watch time, not the streak: the streak has its own
          // card directly below this, with the freeze count and the record on
          // it, and the same number twice on one screen is one number too
          // many.
          _StatTile(
            icon: Icons.calendar_month_rounded,
            value: '${_stats.byDay.length}',
            label: 'profile.stat_days'.tr(),
            onTap: () => WatchStatsPage.open(context),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = Colors.white.withValues(alpha: 0.05);
    return Expanded(
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: AppColors.textSecondary),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HubOverview extends StatelessWidget {
  const _HubOverview();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Two cards, because these are two questions. "What have I saved"
          // and "what have I done" is the first; "where does the app get
          // things, and who is it talking to" is the second. They used to be
          // one card of three rows under an OVERVIEW label, which named
          // nothing and grouped nothing.
          SettingsLabel('profile.section_library'.tr()),
          SettingsCard(
            children: [
              SettingsNavTile(
                icon: Icons.video_library_outlined,
                title: 'profile.library'.tr(),
                subtitle: 'profile.library_subtitle'.tr(),
                onTap: () => context.push('/library'),
              ),
              const SettingsDivider(),
              SettingsNavTile(
                icon: Icons.timeline_rounded,
                title: 'profile.activity'.tr(),
                subtitle: 'profile.activity_subtitle'.tr(),
                featureId: 'stats',
                onTap: () => context.push('/activity'),
              ),
            ],
          ),
          // Matches the gap between sections rather than exceeding it: a
          // bigger break inside a section than between them inverts the
          // hierarchy the labels are drawing.
          const SizedBox(height: 16),
          SettingsLabel('profile.section_content'.tr()),
          const SettingsCard(
            children: [
              // Shown signed out too. Only the paired-TV row inside needs an
              // account; Discord presence, the desktop link and starting a
              // tracker link all work without one, and hiding the whole row
              // hid those with it.
              _ConnectionsHubTile(),
              SettingsDivider(),
              _SourcesHubTile(),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConnectionsHubTile extends StatefulWidget {
  const _ConnectionsHubTile();

  @override
  State<_ConnectionsHubTile> createState() => _ConnectionsHubTileState();
}

class _ConnectionsHubTileState extends State<_ConnectionsHubTile> {
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

  @override
  Widget build(BuildContext context) {
    final names = <String>[
      if (_anilist.isConnected) 'AniList',
      if (_mal.isConnected) 'MAL',
    ];
    return SettingsNavTile(
      icon: Icons.link_rounded,
      title: 'profile.connections'.tr(),
      // The row carries the tracker state when there is any, and says what
      // else is behind it when there is not.
      subtitle: names.isEmpty ? 'profile.connections_subtitle'.tr() : null,
      value: names.isEmpty ? 'profile.not_connected'.tr() : names.join(' · '),
      valueColor: names.isEmpty ? AppColors.textHint : kAnilistBlue,
      onTap: () => context.push('/profile/connections'),
    );
  }
}

class _SourcesHubTile extends StatelessWidget {
  const _SourcesHubTile();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProviderBloc, ProviderState>(
      builder: (context, state) {
        final loaded = state is ProviderLoaded ? state : null;
        final current = loaded?.currentProvider;
        return SettingsNavTile(
          icon: Icons.extension_outlined,
          title: 'profile.sources_title'.tr(),
          valueLeading: current != null && current.image.isNotEmpty
              ? ProviderMark(url: current.image)
              : null,
          value: current?.name ?? loaded?.currentProviderId,
          onTap: () => context.push('/sources'),
        );
      },
    );
  }
}

class _HubWatch extends StatelessWidget {
  const _HubWatch({required this.signedIn});

  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsLabel(
            'profile.section_watch'.tr(),
            featureIds: const ['torrents'],
          ),
          SettingsCard(
            children: [
              SettingsNavTile(
                icon: Icons.live_tv_rounded,
                title: 'navigation.live_tv'.tr(),
                onTap: () => context.push('/live-tv'),
              ),
              // Watch Party hard-requires an account; a guest is not shown a
              // door that opens onto a sign-in wall.
              if (signedIn) ...[
                const SettingsDivider(),
                SettingsNavTile(
                  icon: Icons.groups_rounded,
                  title: 'watch_party.title'.tr(),
                  onTap: () => showPartyEntrySheet(context),
                ),
              ],
              // The torrent engine is a native Android library.
              if (!kIsWeb && Platform.isAndroid) ...[
                const SettingsDivider(),
                SettingsNavTile(
                  icon: Icons.hub_rounded,
                  title: 'torrent.title'.tr(),
                  featureId: 'torrents',
                  onTap: () => context.push('/torrents'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _HubApp extends StatelessWidget {
  const _HubApp();

  static final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsLabel(
            'profile.section_app'.tr(),
            featureIds: const ['home_rails', 'change_source', 'backup'],
          ),
          SettingsCard(
            children: [
              SettingsNavTile(
                icon: Icons.settings_outlined,
                title: 'profile.settings_title'.tr(),
                subtitle: 'profile.settings_subtitle'.tr(),
                onTap: () => context.push('/settings'),
              ),
              const SettingsDivider(),
              FutureBuilder<PackageInfo>(
                future: _packageInfo,
                builder: (context, snap) => SettingsNavTile(
                  icon: Icons.info_outline_rounded,
                  title: 'profile.about'.tr(),
                  value: snap.hasData ? 'v${snap.data!.version}' : null,
                  onTap: () => context.push('/about'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Unread notifications, in the title bar. Signed-in only: the inbox is
/// server-side.
class _HubBell extends StatefulWidget {
  const _HubBell();

  @override
  State<_HubBell> createState() => _HubBellState();
}

class _HubBellState extends State<_HubBell> {
  final NotificationsRepository _repo = getIt<NotificationsRepository>();
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!getIt<HiveService>().isLoggedIn) return;
    final result = await _repo.unreadCount();
    if (!mounted) return;
    if (result case Success(:final value)) {
      if (value != _count) setState(() => _count = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          await context.push('/notifications');
          _refresh();
        },
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            shape: BoxShape.circle,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Center(
                child: Icon(
                  Icons.notifications_none_rounded,
                  color: AppColors.textPrimary,
                  size: 21,
                ),
              ),
              if (_count > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    constraints: const BoxConstraints(
                      minWidth: 15,
                      minHeight: 15,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.navBackground,
                        width: 1.2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _count > 99 ? '99+' : '$_count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
