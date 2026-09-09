import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/bridge/bridge_control.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/discord/discord_brand.dart';
import 'package:soplay/core/discord/discord_presence_service.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_logo.dart';
import 'package:soplay/features/mal/data/mal_service.dart';
import 'package:soplay/features/mal/presentation/widgets/mal_brand.dart';
import 'package:soplay/features/profile/presentation/widgets/settings_tiles.dart';

/// Accounts and devices tied to this one: trackers, Discord, a paired TV,
/// the desktop app.
class ProfileConnectionsPage extends StatefulWidget {
  const ProfileConnectionsPage({super.key});

  @override
  State<ProfileConnectionsPage> createState() => _ProfileConnectionsPageState();
}

class _ProfileConnectionsPageState extends State<ProfileConnectionsPage> {
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

  /// The account name a tracker was linked with, or the service name when the
  /// link carries none yet.
  String _label(String service, String? account) {
    final name = account?.trim();
    return name == null || name.isEmpty ? service : name;
  }

  /// One row, not two.
  ///
  /// AniList and MyAnimeList were a row each and both opened the same screen —
  /// two doors into one room, and neither said which half of it you would land
  /// in. Connecting, disconnecting and what each link writes all live together
  /// on that screen, so the row that opens it says "trackers" and carries both
  /// marks and both states.
  Widget _trackersTile() {
    final connected = <String>[
      if (_anilist.isConnected) _label('AniList', _anilist.viewer?.name),
      if (_mal.isConnected) _label('MyAnimeList', _mal.viewer?.name),
    ];
    return SettingsNavTile(
      leading: _TrackerPair(
        anilist: _anilist.isConnected,
        mal: _mal.isConnected,
      ),
      title: 'profile.trackers'.tr(),
      subtitle: connected.isEmpty ? 'anilist.connect_tagline'.tr() : null,
      value: connected.isEmpty
          ? 'profile.not_connected'.tr()
          : connected.join(' · '),
      valueColor: connected.isEmpty ? AppColors.textHint : kAnilistBlue,
      onTap: () => context.push('/connections'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: 'profile.connections'.tr(),
      children: [
        SettingsLabel('profile.section_accounts'.tr()),
        SettingsCard(
          children: [
            _trackersTile(),
            const SettingsDivider(),
            const _DiscordTile(),
          ],
        ),
        const SizedBox(height: 20),
        SettingsLabel('profile.section_devices'.tr()),
        SettingsCard(
          children: [
            // Every call the pairing makes is account-scoped, so this is the
            // one row here that a guest cannot use.
            if (getIt<HiveService>().isLoggedIn) ...[
              SettingsNavTile(
                icon: Icons.cast_connected_rounded,
                title: 'link_tv.title'.tr(),
                subtitle: 'link_tv.tile_subtitle'.tr(),
                onTap: () => context.push('/link-tv'),
              ),
              const SettingsDivider(),
            ],
            SettingsNavTile(
              icon: Icons.devices_rounded,
              title: BridgeControl.canHost
                  ? 'profile.share_sources_desktop'.tr()
                  : Platform.isIOS
                  ? 'ios.sources_title'.tr()
                  : 'profile.desktop_sources'.tr(),
              onTap: () => context.push('/desktop-share'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Discord's own mark and its live state. Three states, not two: off, on but
/// nothing to talk to, and live. The middle one is why somebody opens this.
class _DiscordTile extends StatelessWidget {
  const _DiscordTile();

  @override
  Widget build(BuildContext context) {
    final on = getIt<HiveService>().discordPresenceEnabled;
    final live = on && getIt<DiscordPresenceService>().isConnected;
    return SettingsNavTile(
      leading: Center(
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: on
                ? DiscordBrand.blurple
                : DiscordBrand.blurple.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Center(
            child: on
                ? DiscordBrand.mark(size: 15)
                : DiscordBrand.muted(size: 15),
          ),
        ),
      ),
      title: 'discord.title'.tr(),
      subtitle: !on
          ? 'discord.row_off'.tr()
          : live
          ? 'discord.row_live'.tr()
          : 'discord.row_waiting'.tr(),
      onTap: () => context.push('/discord'),
    );
  }
}

/// Both tracker marks in one 34px leading slot, each dimmed while that
/// tracker is unlinked — so the row answers "which of the two am I on?"
/// without being read.
class _TrackerPair extends StatelessWidget {
  const _TrackerPair({required this.anilist, required this.mal});

  final bool anilist;
  final bool mal;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 34,
      child: Stack(
        children: [
          PositionedDirectional(
            top: 0,
            start: 0,
            child: Opacity(
              opacity: anilist ? 1 : 0.35,
              child: const AnilistLogo(size: 22, radius: 7),
            ),
          ),
          PositionedDirectional(
            bottom: 0,
            end: 0,
            child: Container(
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(
                // A ring in the card colour, so the lower mark reads as in
                // front of the upper one instead of merging with it.
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8.5),
              ),
              child: Opacity(
                opacity: mal ? 1 : 0.35,
                child: const MalLogo(size: 20, radius: 6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
