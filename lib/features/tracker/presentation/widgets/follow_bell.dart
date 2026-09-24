import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/anilist/data/anilist_link_store.dart';
import 'package:soplay/features/detail/domain/entities/detail_entity.dart';
import 'package:soplay/features/mal/data/mal_link_store.dart';
import 'package:soplay/features/notifications/presentation/widgets/animated_bell.dart';
import 'package:soplay/features/notifications/presentation/widgets/notification_priming.dart';
import 'package:soplay/features/tracker/data/follow_service.dart';
import 'package:soplay/features/tracker/domain/entities/followed_title.dart';
import 'package:soplay/features/tracker/presentation/widgets/release_labels.dart';

/// The follow record for [d], with every id this device can put a name to.
///
/// The ids are what let the server watch a title for us: an AniList id makes
/// an anime checkable from AniList's schedule, a TMDB id a show from TMDB's.
/// They come from the catalogue record when the page has one, and otherwise
/// from a tracker link the user already made for this title.
FollowedTitle followedTitleFor(DetailEntity d) {
  final record = d.record;
  final provider = d.provider;
  int? anilistId = record?.anilistId;
  int? malId = record?.malId;
  try {
    anilistId ??= getIt<AnilistLinkStore>().get(provider, d.contentUrl)?.mediaId;
  } catch (_) {}
  try {
    malId ??= getIt<MalLinkStore>().get(provider, d.contentUrl)?.mediaId;
  } catch (_) {}
  final tmdbUrl = RegExp(
    r'themoviedb\.org/(tv|movie)/(\d+)',
  ).firstMatch(d.contentUrl);
  final tmdbId = record?.tmdbId ?? int.tryParse(tmdbUrl?.group(2) ?? '');
  final tmdbKind = tmdbId == null
      ? null
      : tmdbUrl?.group(1) ?? (d.isSerial ? 'tv' : 'movie');
  return FollowedTitle(
    contentUrl: d.contentUrl,
    provider: provider,
    title: d.title,
    thumbnail: d.thumbnail ?? '',
    year: d.year,
    addedAt: DateTime.now().millisecondsSinceEpoch,
    mode: provider.contentMode.id,
    anilistId: anilistId,
    malId: malId,
    tmdbId: tmdbId,
    tmdbKind: tmdbKind,
    nextAiringAt: record?.nextAiringAt?.millisecondsSinceEpoch,
    nextAiringEpisode: record?.nextEpisode,
  );
}

/// Follows or unfollows [d]. A new follow is where notifications start to
/// matter, so it is also where they are asked for — once, behind the priming
/// sheet, and not again for a while after a "Not now".
Future<bool> toggleFollow(BuildContext context, DetailEntity d) async {
  final service = getIt<FollowService>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (service.isFollowed(d.contentUrl)) {
    final was = service.get(d.contentUrl);
    await service.unfollow(d.contentUrl);
    HapticFeedback.selectionClick();
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('detail.following_off'.tr()),
          behavior: SnackBarBehavior.floating,
          action: was == null
              ? null
              : SnackBarAction(
                  label: 'tracker.undo'.tr(),
                  onPressed: () => unawaited(service.follow(was)),
                ),
        ),
      );
    return false;
  }
  await service.follow(followedTitleFor(d));
  HapticFeedback.mediumImpact();
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('detail.following_on'.tr()),
        behavior: SnackBarBehavior.floating,
      ),
    );
  if (context.mounted) {
    await showNotificationPriming(context, titleHint: d.title);
  }
  return true;
}

/// Mute, unmute or unfollow — the long-press menu of the bell.
Future<void> showFollowMenu(BuildContext context, DetailEntity d) async {
  final service = getIt<FollowService>();
  if (!service.isFollowed(d.contentUrl)) {
    await toggleFollow(context, d);
    return;
  }
  await showAdaptiveModal<void>(
    context: context,
    backgroundColor: AppColors.surface,
    builder: (ctx) => _FollowMenu(detail: d),
  );
}

/// Follow, with the state spelled out: "Follow", "Following", "Muted".
///
/// Tap follows; once following, tap opens the menu (the chevron says so) that
/// mutes this one title or unfollows it.
class FollowBellPill extends StatefulWidget {
  const FollowBellPill({super.key, required this.detail});

  final DetailEntity detail;

  @override
  State<FollowBellPill> createState() => _FollowBellPillState();
}

class _FollowBellPillState extends State<FollowBellPill> {
  final FollowService _service = getIt<FollowService>();
  FollowedTitle? _title;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service.revision.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _service.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _title = _service.get(widget.detail.contentUrl));
  }

  Future<void> _tap() async {
    if (_busy) return;
    _busy = true;
    try {
      await showFollowMenu(context, widget.detail);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _title;
    final state = t == null
        ? BellState.off
        : t.notify
        ? BellState.on
        : BellState.muted;
    final reading = widget.detail.provider.contentMode != ContentMode.video;
    final label = switch (state) {
      BellState.off => 'release_notify.follow'.tr(),
      BellState.on => 'release_notify.following'.tr(),
      BellState.muted => 'release_notify.muted'.tr(),
    };
    final on = state == BellState.on;
    final fg = on ? AppColors.primary : AppColors.textPrimary;
    final hint = t == null ? null : nextAiringHint(t, reading: reading);

    return Row(
      children: [
        Semantics(
          button: true,
          toggled: t != null,
          label: 'release_notify.follow_tooltip'.tr(),
          child: HoverTap(
            onTap: _tap,
            onLongPress: () => showFollowMenu(context, widget.detail),
            onSecondaryTap: () => showFollowMenu(context, widget.detail),
            borderRadius: 22,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: const Cubic(0.05, 0.7, 0.1, 1.0),
              height: 40,
              padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 6, 0),
              decoration: BoxDecoration(
                color: on
                    ? AppColors.primary.withValues(alpha: 0.16)
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: on
                      ? AppColors.primary.withValues(alpha: 0.55)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBell(state: state, color: fg, size: 20),
                  const SizedBox(width: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      label,
                      key: ValueKey(label),
                      style: TextStyle(
                        color: fg,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (t != null)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 2),
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 18,
                        color: fg.withValues(alpha: 0.8),
                      ),
                    )
                  else
                    const SizedBox(width: 6),
                ],
              ),
            ),
          ),
        ),
        if (hint != null) ...[
          const SizedBox(width: 10),
          Flexible(
            child: Row(
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  size: 14,
                  color: AppColors.textHint,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _FollowMenu extends StatefulWidget {
  const _FollowMenu({required this.detail});

  final DetailEntity detail;

  @override
  State<_FollowMenu> createState() => _FollowMenuState();
}

class _FollowMenuState extends State<_FollowMenu> {
  final FollowService _service = getIt<FollowService>();
  late bool _notify =
      _service.get(widget.detail.contentUrl)?.notify ?? true;

  Future<void> _setNotify(bool on) async {
    HapticFeedback.selectionClick();
    setState(() => _notify = on);
    await _service.setNotify(widget.detail.contentUrl, on);
    if (on && mounted) {
      await showNotificationPriming(context, titleHint: widget.detail.title);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reading = widget.detail.provider.contentMode != ContentMode.video;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 10),
              child: Text(
                widget.detail.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            SwitchListTile(
              value: _notify,
              onChanged: _setNotify,
              secondary: AnimatedBell(
                state: _notify ? BellState.on : BellState.muted,
                color: _notify ? AppColors.primary : AppColors.textSecondary,
              ),
              title: Text(
                reading
                    ? 'release_notify.notify_on_reading'.tr()
                    : 'release_notify.notify_on'.tr(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'release_notify.notify_on_desc'.tr(),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.remove_circle_outline_rounded,
                color: AppColors.errorLight,
              ),
              title: Text(
                'release_notify.unfollow'.tr(),
                style: const TextStyle(
                  color: AppColors.errorLight,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                await _service.unfollow(widget.detail.contentUrl);
                HapticFeedback.selectionClick();
              },
            ),
          ],
        ),
      ),
    );
  }
}
