import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:soplay/features/remote/data/remote_control_service.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/anilist/data/anilist_link_store.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_link_sheet.dart';
import 'package:soplay/features/mal/data/mal_link_store.dart';
import 'package:soplay/features/mal/data/mal_service.dart';
import 'package:soplay/features/mal/presentation/widgets/mal_brand.dart';
import 'package:soplay/features/mal/presentation/widgets/mal_link_sheet.dart';
import 'package:soplay/features/my_list/domain/entities/favorite_entity.dart';
import 'package:soplay/features/reports/presentation/widgets/report_sheet.dart';
import 'package:soplay/features/user_lists/domain/entities/user_list_kind.dart';
import 'package:soplay/features/user_lists/domain/repositories/user_lists_repository.dart';

/// The overflow menu behind the title screen's three-dot button.
///
/// It hangs off the button rather than rising from the bottom of the screen: a
/// half-height sheet for seven short rows buried the poster the user is looking
/// at, and put the rows as far from the button that opened them as the screen
/// allows.
///
/// Still hand-built rather than a [PopupMenuButton], because half of these
/// entries are toggles: the row has to say whether the title is already in
/// Watch Later or tracked on AniList, which a bare menu of labels cannot.
Future<void> showDetailMoreMenu(
  BuildContext context, {
  required GlobalKey anchorKey,
  required FavoriteEntity entity,
  required bool showFollow,
  required bool isFollowing,
  required VoidCallback onToggleFollow,
  required VoidCallback onFindSources,
  required VoidCallback onShare,
  required String shareUrl,
  required bool inPrivate,
  required VoidCallback onMoveToPrivate,
  required VoidCallback onPrivateActions,
}) {
  final anchor = _anchorRect(anchorKey, context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 190),
    // The menu is built here, not in the transition: the transition builder
    // runs every frame of the animation, and rebuilding the rows through it
    // would re-run their state reads a dozen times on the way in.
    pageBuilder: (_, _, _) => _DetailMoreMenu(
      entity: entity,
      showFollow: showFollow,
      isFollowing: isFollowing,
      onToggleFollow: onToggleFollow,
      onFindSources: onFindSources,
      onShare: onShare,
      shareUrl: shareUrl,
      inPrivate: inPrivate,
      onMoveToPrivate: onMoveToPrivate,
      onPrivateActions: onPrivateActions,
    ),
    transitionBuilder: (_, animation, _, child) => _AnchoredMenu(
      anchor: anchor,
      animation: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
      child: child,
    ),
  );
}

/// Where the three-dot button sits, in global coordinates.
///
/// Falls back to the top-right corner when the button has gone — the menu can
/// still be opened by a shortcut on a frame where the bar is rebuilding.
Rect _anchorRect(GlobalKey key, BuildContext context) {
  final box = key.currentContext?.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) {
    final size = MediaQuery.sizeOf(context);
    final top = MediaQuery.paddingOf(context).top + 12;
    return Rect.fromLTWH(size.width - 48, top, 36, 36);
  }
  final origin = box.localToGlobal(Offset.zero);
  return origin & box.size;
}

/// Lays the menu under the anchor, pinned to the same edge, and grows it out of
/// that corner. Clamped to the safe area so a long menu on a short phone slides
/// up instead of hanging off the bottom.
class _AnchoredMenu extends StatelessWidget {
  const _AnchoredMenu({
    required this.anchor,
    required this.animation,
    required this.child,
  });

  final Rect anchor;
  final Animation<double> animation;
  final Widget child;

  static const double _width = 292;
  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final rightAligned = anchor.center.dx > size.width / 2;

    final left = rightAligned
        ? (anchor.right - _width).clamp(12.0, size.width - _width - 12)
        : anchor.left.clamp(12.0, size.width - _width - 12);
    final top = anchor.bottom + _gap;
    final maxHeight = size.height - top - pad.bottom - 16;

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: _width,
          child: FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1).animate(animation),
              alignment: rightAligned ? Alignment.topRight : Alignment.topLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: child,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailMoreMenu extends StatefulWidget {
  const _DetailMoreMenu({
    required this.entity,
    required this.showFollow,
    required this.isFollowing,
    required this.onToggleFollow,
    required this.onFindSources,
    required this.onShare,
    required this.shareUrl,
    required this.inPrivate,
    required this.onMoveToPrivate,
    required this.onPrivateActions,
  });

  final FavoriteEntity entity;
  final bool showFollow;
  final bool isFollowing;
  final VoidCallback onToggleFollow;
  final VoidCallback onFindSources;
  final VoidCallback onShare;

  /// The same link Share sends — held here so Copy can hand it over without
  /// opening the system sheet, which is three taps for something people paste.
  final String shareUrl;

  /// Already in the PIN-locked list, so the row offers the way out instead.
  final bool inPrivate;
  final VoidCallback onMoveToPrivate;
  final VoidCallback onPrivateActions;

  @override
  State<_DetailMoreMenu> createState() => _DetailMoreMenuState();
}

class _DetailMoreMenuState extends State<_DetailMoreMenu> {
  /// Hands this title to a linked TV.
  ///
  /// The device list is fetched on tap rather than when the sheet opens: most
  /// people never press this, and the ones who do can wait for one request
  /// instead of everyone paying for it on every open.
  ///
  /// The TITLE is what travels. The two apps do not share a source registry, so
  /// this app's contentUrl means nothing to a TV without that provider — the TV
  /// resolves the title against its own sources.
  bool _sendingToTv = false;

  Future<void> _playOnTv() async {
    if (_sendingToTv) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final service = getIt<RemoteControlService>();

    void say(String message) => messenger.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );

    setState(() => _sendingToTv = true);
    try {
      final devices = await service.devices();

      if (devices.isEmpty) {
        say('remote.no_devices'.tr());
        return;
      }

      // Always ask, and list the offline TVs too. Sending straight to the only
      // online TV read as nothing having happened, and an offline one came back
      // as a bare failure with no hint that the fix is to open the app on it.
      final target = await _pickDevice(devices);
      if (target == null) return;
      if (!target.online) {
        say('remote.turn_tv_on'.tr());
        return;
      }

      await service.openOnTv(
        target.id,
        title: widget.entity.title,
        contentUrl: widget.entity.contentUrl,
        provider: widget.entity.provider,
      );
      if (!mounted) return;
      navigator.pop();
      say('remote.sent_to_tv'.tr(namedArgs: {'device': target.name}));
    } on RemoteOfflineException {
      say('remote.tv_offline'.tr());
    } catch (_) {
      say('remote.command_failed'.tr());
    } finally {
      if (mounted) setState(() => _sendingToTv = false);
    }
  }

  Future<RemoteDevice?> _pickDevice(List<RemoteDevice> devices) {
    return showModalBottomSheet<RemoteDevice>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'remote.pick_device'.tr(),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              // Offline TVs are listed too, and say so. Hiding them turned "the
              // TV is asleep" into "you have no TVs", which is a different
              // problem with a different answer.
              for (final device in devices)
                ListTile(
                  leading: Icon(
                    device.online ? Icons.tv_rounded : Icons.tv_off_rounded,
                    color: device.online
                        ? AppColors.textSecondary
                        : AppColors.textHint,
                  ),
                  title: Text(
                    device.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: device.online
                          ? AppColors.textPrimary
                          : AppColors.textHint,
                    ),
                  ),
                  subtitle: Text(
                    device.online
                        ? 'remote.device_online'.tr()
                        : 'remote.device_offline'.tr(),
                    style: TextStyle(
                      color: device.online
                          ? AppColors.success
                          : AppColors.textHint,
                      fontSize: 12,
                    ),
                  ),
                  onTap: () => Navigator.of(sheetContext).pop(device),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  final UserListSync _listSync = UserListSync();
  late bool _following = widget.isFollowing;

  @override
  void dispose() {
    _listSync.dispose();
    super.dispose();
  }

  void _toggleFollow() {
    setState(() => _following = !_following);
    widget.onToggleFollow();
  }

  void _run(VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  Future<void> _copyLink() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await Clipboard.setData(ClipboardData(text: widget.shareUrl));
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text('detail.link_copied'.tr()),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _report() async {
    final navigator = Navigator.of(context);
    final entity = widget.entity;
    navigator.pop();
    await showReportSheet(
      context,
      targetType: 'content',
      targetId: entity.contentUrl,
      provider: entity.provider,
      contentUrl: entity.contentUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasUrl = widget.entity.contentUrl.isNotEmpty;
    final anilistReady = getIt<AnilistService>().isConnected && hasUrl;
    final malReady = getIt<MalService>().isConnected && hasUrl;

    // Material, not a bare DecoratedBox: every row in here is an InkWell, and
    // the sheet this replaced was quietly providing the surface they ink onto.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x73000000),
            blurRadius: 28,
            spreadRadius: -6,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Material(
            color: AppColors.surface.withValues(alpha: 0.94),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The poster and the source, not just a line of text: this menu
                // can be opened from a page whose artwork has scrolled away, and
                // every row below acts on THIS title from THAT source.
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 11),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.entity.thumbnail.isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: CachedNetworkImage(
                            imageUrl: widget.entity.thumbnail,
                            width: 38,
                            height: 54,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => SizedBox(
                              width: 38,
                              height: 54,
                              child: ColoredBox(color: AppColors.surfaceVariant),
                            ),
                            errorWidget: (_, _, _) => SizedBox(
                              width: 38,
                              height: 54,
                              child: ColoredBox(color: AppColors.surfaceVariant),
                            ),
                          ),
                        ),
                        const SizedBox(width: 11),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.entity.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                height: 1.25,
                              ),
                            ),
                            if (widget.entity.provider.trim().isNotEmpty) ...[
                              const SizedBox(height: 5),
                              Text(
                                widget.entity.provider,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textHint,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(
                  color: AppColors.divider.withValues(alpha: 0.7),
                  height: 1,
                  indent: 14,
                  endIndent: 14,
                ),
                const SizedBox(height: 6),
                // The title stays pinned and only the actions scroll, so a short
                // screen or a large system font never hides which title this is.
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        UserListToggle(
                          kind: UserListKind.watchLater,
                          entity: widget.entity,
                          sync: _listSync,
                          builder: (_, active, toggle) => _MenuRow(
                            icon: active
                                ? Icons.watch_later_rounded
                                : Icons.watch_later_outlined,
                            label: 'detail.watch_later'.tr(),
                            active: active,
                            onTap: toggle,
                          ),
                        ),
                        UserListToggle(
                          kind: UserListKind.watched,
                          entity: widget.entity,
                          sync: _listSync,
                          builder: (_, active, toggle) => _MenuRow(
                            icon: active
                                ? Icons.visibility_rounded
                                : Icons.visibility_outlined,
                            label: 'detail.watched'.tr(),
                            active: active,
                            onTap: toggle,
                          ),
                        ),
                        if (widget.showFollow)
                          _MenuRow(
                            icon: _following
                                ? Icons.notifications_active_rounded
                                : Icons.notifications_none_rounded,
                            label: 'detail.follow_series'.tr(),
                            active: _following,
                            onTap: _toggleFollow,
                          ),
                        if (anilistReady) _AnilistRow(entity: widget.entity),
                        if (malReady) _MalRow(entity: widget.entity),
                        _MenuRow(
                          icon: widget.inPrivate
                              ? Icons.lock_rounded
                              : Icons.lock_outline_rounded,
                          label: widget.inPrivate
                              ? 'app_lock.private_list'.tr()
                              : 'app_lock.move_to_private'.tr(),
                          active: widget.inPrivate,
                          onTap: () => _run(
                            widget.inPrivate
                                ? widget.onPrivateActions
                                : widget.onMoveToPrivate,
                          ),
                        ),
                        Divider(
                          color: AppColors.divider,
                          height: 13,
                          indent: 16,
                          endIndent: 16,
                        ),
                        _MenuRow(
                          icon: Icons.travel_explore_rounded,
                          label: 'detail.find_other_sources'.tr(),
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.textHint,
                            size: 20,
                          ),
                          onTap: () => _run(widget.onFindSources),
                        ),
                        _MenuRow(
                          icon: Icons.cast_rounded,
                          label: 'remote.open_on_tv'.tr(),
                          // Looking up the linked TVs is a network round trip; without
                          // a spinner the row looked dead until the picker appeared.
                          trailing: _sendingToTv
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.textSecondary,
                                  ),
                                )
                              : const Icon(
                                  Icons.chevron_right_rounded,
                                  color: AppColors.textHint,
                                  size: 20,
                                ),
                          onTap: _sendingToTv ? null : _playOnTv,
                        ),
                        _MenuRow(
                          icon: Icons.ios_share_rounded,
                          label: 'movie.share'.tr(),
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.textHint,
                            size: 20,
                          ),
                          onTap: () => _run(widget.onShare),
                        ),
                        _MenuRow(
                          icon: Icons.link_rounded,
                          label: 'detail.copy_link'.tr(),
                          onTap: _copyLink,
                        ),
                        Divider(
                          color: AppColors.divider,
                          height: 13,
                          indent: 16,
                          endIndent: 16,
                        ),
                        // A title whose source is broken is the commonest thing
                        // a viewer wants to tell someone about, and the only
                        // place to report one was under a comment.
                        _MenuRow(
                          icon: Icons.flag_outlined,
                          label: 'detail.report_problem'.tr(),
                          onTap: _report,
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
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

/// Fires after any [UserListToggle] writes, so sibling toggles re-read the
/// cache: marking a title Watched evicts it from Watch Later.
class UserListSync extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// Holds the membership state of one user-curated list and hands it to
/// [builder], so a circle button and a sheet row share the same logic.
///
/// The repository writes its cache before the network, so the flip is immediate
/// and survives a failed request — no spinner, no rollback dance.
class UserListToggle extends StatefulWidget {
  const UserListToggle({
    super.key,
    required this.kind,
    required this.entity,
    required this.builder,
    this.sync,
  });

  final UserListKind kind;
  final FavoriteEntity entity;
  final UserListSync? sync;
  final Widget Function(BuildContext context, bool active, VoidCallback toggle)
  builder;

  @override
  State<UserListToggle> createState() => _UserListToggleState();
}

class _UserListToggleState extends State<UserListToggle> {
  late bool _active = _read();

  bool _read() => getIt<UserListsRepository>().contains(
    widget.kind,
    widget.entity.contentUrl,
  );

  @override
  void initState() {
    super.initState();
    widget.sync?.addListener(_reread);
  }

  @override
  void didUpdateWidget(covariant UserListToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sync != widget.sync) {
      oldWidget.sync?.removeListener(_reread);
      widget.sync?.addListener(_reread);
    }
    // The same toggle is reused when the page rebinds to another title.
    if (oldWidget.entity.contentUrl != widget.entity.contentUrl) {
      _active = _read();
    }
  }

  @override
  void dispose() {
    widget.sync?.removeListener(_reread);
    super.dispose();
  }

  void _reread() {
    final active = _read();
    if (mounted && active != _active) setState(() => _active = active);
  }

  Future<void> _toggle() async {
    final repo = getIt<UserListsRepository>();
    final next = !_active;
    setState(() => _active = next);
    if (next) {
      await repo.add(widget.kind, widget.entity);
    } else {
      await repo.remove(widget.kind, widget.entity.contentUrl);
    }
    if (mounted) widget.sync?.ping();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _active, _toggle);
}

class _AnilistRow extends StatefulWidget {
  const _AnilistRow({required this.entity});

  final FavoriteEntity entity;

  @override
  State<_AnilistRow> createState() => _AnilistRowState();
}

class _MalRow extends StatefulWidget {
  const _MalRow({required this.entity});

  final FavoriteEntity entity;

  @override
  State<_MalRow> createState() => _MalRowState();
}

/// The MyAnimeList twin of [_AnilistRow].
///
/// Shown only when MAL is connected, so a user of one tracker never sees the
/// other's row. Most MAL links are made automatically through AniList's
/// `idMal`; this is how a wrong one gets corrected, and how a title AniList has
/// no MAL counterpart for gets linked at all.
class _MalRowState extends State<_MalRow> {
  late MalLink? _link = getIt<MalLinkStore>().get(
    widget.entity.provider,
    widget.entity.contentUrl,
  );

  Future<void> _open() async {
    await MalLinkSheet.show(
      context,
      provider: widget.entity.provider,
      contentUrl: widget.entity.contentUrl,
      title: widget.entity.title,
    );
    if (!mounted) return;
    setState(
      () => _link = getIt<MalLinkStore>().get(
        widget.entity.provider,
        widget.entity.contentUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final linked = _link != null;
    return _MenuRow(
      icon: linked ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined,
      label: linked ? 'mal.tracked'.tr() : 'mal.track'.tr(),
      active: linked,
      accent: kMalBlue,
      onTap: _open,
    );
  }
}

class _AnilistRowState extends State<_AnilistRow> {
  late AnilistLink? _link = getIt<AnilistLinkStore>().get(
    widget.entity.provider,
    widget.entity.contentUrl,
  );

  Future<void> _open() async {
    await AnilistLinkSheet.show(
      context,
      provider: widget.entity.provider,
      contentUrl: widget.entity.contentUrl,
      title: widget.entity.title,
    );
    if (!mounted) return;
    setState(
      () => _link = getIt<AnilistLinkStore>().get(
        widget.entity.provider,
        widget.entity.contentUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final linked = _link != null;
    return _MenuRow(
      icon: linked ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined,
      label: linked
          ? 'detail.anilist_tracked'.tr()
          : 'detail.anilist_track'.tr(),
      active: linked,
      accent: kAnilistBlue,
      onTap: _open,
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.accent = AppColors.rating,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final Color accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: active
                      ? accent.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: active ? accent : AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              trailing ??
                  (active
                      ? Icon(Icons.check_rounded, size: 20, color: accent)
                      : const SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
  }
}
