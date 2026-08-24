import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';
import 'package:soplay/features/anilist/data/anilist_link_store.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_logo.dart';
import 'package:soplay/features/mal/data/mal_link_store.dart';
import 'package:soplay/features/mal/data/mal_service.dart';
import 'package:soplay/features/mal/presentation/widgets/mal_brand.dart';

/// External accounts this app can write to.
///
/// One screen for both trackers: the connection has consequences the user needs
/// stated in one place — what gets written, and how to stop it — and those do
/// not belong scattered through Settings.
class ConnectionsPage extends StatefulWidget {
  const ConnectionsPage({super.key});

  @override
  State<ConnectionsPage> createState() => _ConnectionsPageState();
}

class _ConnectionsPageState extends State<ConnectionsPage> {
  final AnilistService _anilist = getIt<AnilistService>();
  final AnilistLinkStore _links = getIt<AnilistLinkStore>();
  final MalService _mal = getIt<MalService>();
  final MalLinkStore _malLinks = getIt<MalLinkStore>();

  @override
  void initState() {
    super.initState();
    _anilist.addListener(_onAnilistChange);
    _mal.addListener(_onMalChange);
  }

  @override
  void dispose() {
    _anilist.removeListener(_onAnilistChange);
    _mal.removeListener(_onMalChange);
    super.dispose();
  }

  void _onAnilistChange() => _onChange(_anilist.consumeError);

  void _onMalChange() => _onChange(_mal.consumeError);

  void _onChange(String? Function() takeError) {
    if (!mounted) return;
    setState(() {});
    final error = takeError();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
      );
    }
  }

  /// Both links are stored against the Sozo account, so there has to be one.
  ///
  /// Rather than saying so and stopping — which left the user holding a message
  /// and no way to act on it — this goes to the login screen and carries on
  /// with the link when they come back signed in.
  Future<bool> _ensureSignedIn() async {
    if (getIt<HiveService>().isLoggedIn) return true;
    await context.push('/login');
    if (!mounted) return false;
    return getIt<HiveService>().isLoggedIn;
  }

  Future<void> _connectAnilist() async {
    if (!await _ensureSignedIn()) return;
    final opened = await _anilist.beginLink();
    if (!opened && mounted) _sayBrowserFailed();
  }

  Future<void> _connectMal() async {
    if (!await _ensureSignedIn()) return;
    // MalService parks its own reason in consumeError (MAL not configured
    // server-side, for one), and the listener shows it — so a bare "could not
    // open the browser" would overwrite the more specific message.
    final opened = await _mal.beginLink();
    if (!opened && mounted && _mal.consumeError() == null) _sayBrowserFailed();
  }

  void _sayBrowserFailed() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('anilist.browser_failed'.tr()),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<bool> _confirmDisconnect(String title, String body) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          title,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 17),
        ),
        content: Text(
          body,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('general.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'anilist.disconnect'.tr(),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _disconnectAnilist() async {
    if (!await _confirmDisconnect(
      'anilist.disconnect'.tr(),
      'anilist.disconnect_confirm'.tr(),
    )) {
      return;
    }
    await _anilist.disconnect();
    // The title-to-media map describes THIS account's shows; keeping it after a
    // disconnect would silently reattach them if a different AniList account
    // were connected next.
    await _links.clear();
  }

  Future<void> _disconnectMal() async {
    if (!await _confirmDisconnect(
      'mal.disconnect'.tr(),
      'mal.disconnect_confirm'.tr(),
    )) {
      return;
    }
    await _mal.disconnect();
    await _malLinks.clear();
  }

  @override
  Widget build(BuildContext context) {
    final viewer = _anilist.viewer;
    final connected = _anilist.isConnected;
    final linkCount = _links.all().length;

    final malViewer = _mal.viewer;
    final malConnected = _mal.isConnected;
    final malLinkCount = _malLinks.all().length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Text(
          'anilist.connections_title'.tr(),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _TrackerCard(
            name: 'AniList',
            accent: kAnilistBlue,
            connected: connected,
            busy: _anilist.linking,
            accountName: viewer?.name,
            avatarUrl: viewer?.avatarUrl,
            placeholder: const AnilistLogo(size: 30),
            explainer: connected
                ? 'anilist.connected_explainer'.tr()
                : 'anilist.connect_explainer'.tr(),
            connectLabel: 'anilist.connect'.tr(),
            onConnect: _connectAnilist,
            onDisconnect: _disconnectAnilist,
          ),
          // Outside the `connected` block on purpose: the schedule is public.
          const SizedBox(height: 12),
          _Row(
            icon: Icons.calendar_month_rounded,
            title: 'anilist.calendar_open'.tr(),
            accent: kAnilistBlue,
            onTap: () => context.push('/anilist/calendar'),
          ),
          if (connected) ...[
            const SizedBox(height: 8),
            _Row(
              icon: Icons.auto_awesome_motion_rounded,
              title: 'anilist.open_library'.tr(),
              accent: kAnilistBlue,
              onTap: () => context.push('/anilist'),
            ),
            const SizedBox(height: 8),
            _Row(
              icon: Icons.link_rounded,
              title: 'anilist.linked_titles'.tr(),
              accent: kAnilistBlue,
              subtitle: linkCount > 0
                  ? 'anilist.linked_titles_count'.tr(args: ['$linkCount'])
                  : 'anilist.linked_titles_none'.tr(),
              onTap: linkCount == 0
                  ? null
                  : () async {
                      await context.push('/anilist/links');
                      if (mounted) setState(() {});
                    },
            ),
          ],

          const SizedBox(height: 20),
          _TrackerCard(
            name: 'MyAnimeList',
            accent: kMalBlue,
            connected: malConnected,
            busy: _mal.linking,
            accountName: malViewer?.name,
            avatarUrl: malViewer?.avatarUrl,
            placeholder: const MalLogo(size: 30),
            explainer: malConnected
                ? 'mal.connected_explainer'.tr()
                : 'mal.connect_explainer'.tr(),
            connectLabel: 'mal.connect'.tr(),
            onConnect: _connectMal,
            onDisconnect: _disconnectMal,
          ),
          if (malConnected) ...[
            const SizedBox(height: 12),
            _Row(
              icon: Icons.auto_awesome_motion_rounded,
              accent: kMalBlue,
              title: 'mal.open_library'.tr(),
              onTap: () => context.push('/mal'),
            ),
            const SizedBox(height: 8),
            _Row(
              icon: Icons.link_rounded,
              accent: kMalBlue,
              title: 'mal.linked_titles'.tr(),
              subtitle: malLinkCount > 0
                  ? 'anilist.linked_titles_count'.tr(args: ['$malLinkCount'])
                  : 'anilist.linked_titles_none'.tr(),
              onTap: malLinkCount == 0
                  ? null
                  : () async {
                      await context.push('/mal/links');
                      if (mounted) setState(() {});
                    },
            ),
            const SizedBox(height: 8),
            _Row(
              icon: Icons.info_outline_rounded,
              accent: kMalBlue,
              title: 'mal.matching_title'.tr(),
              subtitle: 'mal.matching_note'.tr(),
              onTap: null,
            ),
          ],

          const SizedBox(height: 18),
          Text(
            'mal.privacy_note'.tr(),
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// One tracker's connect / disconnect card.
///
/// Extracted the moment there were two: the copy differs, the accent differs,
/// and everything else — the avatar fallback, the busy spinner, the button
/// swap — is identical, which is exactly the part worth having in one place.
class _TrackerCard extends StatelessWidget {
  const _TrackerCard({
    required this.name,
    required this.accent,
    required this.connected,
    required this.busy,
    required this.accountName,
    required this.avatarUrl,
    required this.placeholder,
    required this.explainer,
    required this.connectLabel,
    required this.onConnect,
    required this.onDisconnect,
  });

  final String name;
  final Color accent;
  final bool connected;
  final bool busy;
  final String? accountName;
  final String? avatarUrl;
  final Widget placeholder;
  final String explainer;
  final String connectLabel;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final named = connected && (accountName?.isNotEmpty ?? false);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: connected ? accent.withValues(alpha: 0.35) : AppColors.border,
          width: connected ? 1 : 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(
                url: avatarUrl,
                connected: connected,
                accent: accent,
                placeholder: placeholder,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      named ? accountName! : 'anilist.not_connected'.tr(),
                      style: TextStyle(
                        color: connected ? accent : AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            explainer,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: connected
                ? OutlinedButton.icon(
                    onPressed: onDisconnect,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(kButtonRadius),
                      ),
                    ),
                    icon: const Icon(Icons.link_off_rounded, size: 18),
                    label: Text('anilist.disconnect'.tr()),
                  )
                : FilledButton.icon(
                    onPressed: busy ? null : onConnect,
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(kButtonRadius),
                      ),
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(
                      connectLabel,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.url,
    required this.connected,
    required this.accent,
    required this.placeholder,
  });

  final String? url;
  final bool connected;
  final Color accent;
  final Widget placeholder;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: connected ? AppColors.surfaceVariant : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: (connected && url != null && url!.isNotEmpty)
          ? CachedNetworkImage(
              imageUrl: url!,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => const Icon(
                Icons.person_rounded,
                color: AppColors.textHint,
              ),
            )
          : Center(child: placeholder),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.onTap,
    required this.accent,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(icon, color: enabled ? accent : AppColors.textHint, size: 21),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: enabled
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (enabled)
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textHint, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
