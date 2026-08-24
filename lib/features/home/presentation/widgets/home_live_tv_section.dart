import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';
import 'package:soplay/features/live_tv/data/live_tv_service.dart';

/// Live TV, where somebody might actually find it.
///
/// The line-up was reachable only through Profile → Live TV, seven rows down a
/// settings list, which is a fine place for a preference and the wrong place for
/// a thousand channels. Live TV is content; it belongs where the content is.
///
/// A rail rather than a link: a channel is chosen in a second and watched
/// immediately, so the row IS the feature — tap a logo and it plays. The header
/// still opens the full page for browsing folders and searching.
///
/// Self-collapsing. It fetches on its own and renders nothing at all until it
/// has channels, so a backend without a line-up (or without a network) leaves
/// Home exactly as it was rather than showing an empty shelf or an error.
class LiveTvSection extends StatefulWidget {
  const LiveTvSection({super.key});

  /// How many logos to pull. Enough to fill the rail on a tablet and to feel
  /// like a line-up rather than a shortcut, without paging a phone's Home.
  static const int _limit = 20;

  @override
  State<LiveTvSection> createState() => _LiveTvSectionState();
}

class _LiveTvSectionState extends State<LiveTvSection> {
  List<LiveChannel> _channels = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final page = await getIt<LiveTvService>().browse(
        limit: LiveTvSection._limit,
      );
      if (!mounted) return;
      setState(() => _channels = page.channels);
    } catch (_) {
      // Offline, or a backend with no line-up. Home simply does not grow a
      // Live TV row, which is the right failure for something nobody asked for
      // on this screen.
    }
  }

  void _play(LiveChannel channel) {
    // Live TV's own "Recently watched" rail is fed from here as well as from
    // its page: a channel played from Home is still a channel you watched, and
    // the card is what lets the rail draw it without its listing.
    final hive = getIt<HiveService>();
    hive.pushLiveTvRecent(channel.id);
    final cards = hive.getLiveTvCards();
    cards[channel.id] = {
      'name': channel.name,
      'streamUrl': channel.streamUrl,
      'logoUrl': channel.logoUrl ?? '',
      'category': channel.category,
      if (channel.headers.isNotEmpty) 'headers': jsonEncode(channel.headers),
    };
    hive.setLiveTvCards(cards);
    context.push(
      '/player',
      extra: PlayerArgs(
        title: channel.name,
        provider: 'live',
        headers: channel.headers,
        movieUrl: channel.streamUrl,
        thumbnail: channel.logoUrl,
        // Live has nothing to resume to and no end to download.
        type: 'live',
        showDownloadAction: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_channels.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => context.push('/live-tv'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(17, 18, 20, 14),
              child: Row(
                children: [
                  const Icon(
                    Icons.live_tv_rounded,
                    color: AppColors.textSecondary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'live_tv.title'.tr(),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const _LiveBadge(),
                  const Spacer(),
                  Text(
                    'home.view_all'.tr(),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textSecondary,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: _channels.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) =>
                  _ChannelTile(channel: _channels[i], onTap: _play),
            ),
          ),
        ],
      ),
    );
  }
}

/// One channel: its logo, and its name underneath.
///
/// Logo-forward and square, because a channel is recognised by its mark long
/// before its name is read — which is the whole difference between scanning a
/// line-up and reading a list.
class _ChannelTile extends StatelessWidget {
  const _ChannelTile({required this.channel, required this.onTap});

  final LiveChannel channel;
  final ValueChanged<LiveChannel> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onTap(channel),
              child: Container(
                width: 76,
                height: 76,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: channel.logoUrl == null
                    ? const Icon(
                        Icons.live_tv_rounded,
                        size: 26,
                        color: AppColors.textHint,
                      )
                    : CachedNetworkImage(
                        imageUrl: channel.logoUrl!,
                        fit: BoxFit.contain,
                        // A broadcaster's mark is drawn for a light background
                        // as often as not, so it is never tinted or cropped —
                        // just fitted, and given a neutral tile to sit on.
                        errorWidget: (_, _, _) => const Icon(
                          Icons.live_tv_rounded,
                          size: 26,
                          color: AppColors.textHint,
                        ),
                        placeholder: (_, _) => const SizedBox.shrink(),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            channel.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The small red-dot LIVE marker.
///
/// Static rather than pulsing: this sits in a scrolling feed, and an animation
/// running forever on Home costs a frame callback for the whole session to say
/// something a colour already says.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            // Not const: the accent is a user setting, so AppColors.primary is
            // a getter and cannot appear in a constant expression.
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'LIVE',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
