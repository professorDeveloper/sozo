import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/discord/discord_activity.dart';
import 'package:soplay/core/discord/discord_brand.dart';

/// What the viewer's friends actually see, drawn as Discord draws it.
///
/// ## Why show this rather than describe it
///
/// "Shows what you are watching on your profile" is a sentence somebody has to
/// take on trust before handing over a credential. A picture of the card
/// answers the two questions they actually have — *what exactly appears* and
/// *is it working right now* — without either of them being asked.
///
/// It doubles as the connection indicator. Live activity means the transport
/// is up and Discord accepted the last update; a placeholder means it is not,
/// and no separate "connected" claim has to be believed.
///
/// The geometry follows Discord's own activity card: 60pt rounded art on the
/// left, three text rows, and the elapsed line last. Close enough that
/// somebody recognises it, not a pixel copy — this is a preview, not a
/// counterfeit of Discord's UI.
class DiscordPreviewCard extends StatelessWidget {
  const DiscordPreviewCard({
    super.key,
    required this.activity,
    required this.connected,
    this.appName = 'Sozo',
  });

  /// Null when nothing is playing, which is the ordinary state on a settings
  /// screen — the placeholder then shows the shape rather than pretending.
  final DiscordActivity? activity;

  final bool connected;
  final String appName;

  @override
  Widget build(BuildContext context) {
    final live = activity;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: DiscordBrand.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Discord's own section heading above an activity.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: connected
                        ? DiscordBrand.online
                        : DiscordBrand.offline,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'discord.preview_heading'.tr(),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Art(url: live?.imageUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      _Line(
                        text: live?.title,
                        placeholder: 'discord.preview_title'.tr(),
                        strong: true,
                      ),
                      const SizedBox(height: 2),
                      _Line(
                        text: live?.subtitle,
                        placeholder: 'discord.preview_subtitle'.tr(),
                      ),
                      const SizedBox(height: 2),
                      _Line(
                        text: live?.startedAt == null
                            ? null
                            : 'discord.preview_elapsed'.tr(
                                args: [_elapsed(live!.startedAt!)],
                              ),
                        placeholder: 'discord.preview_elapsed_placeholder'.tr(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// `12:34 elapsed`, counted from the timestamp Discord was given.
  ///
  /// Recomputed on each build rather than ticked: this card is on a settings
  /// screen nobody watches for a minute, and a timer here would keep the whole
  /// page rebuilding for a line that does not need to be to the second.
  static String _elapsed(DateTime start) {
    final d = DateTime.now().difference(start);
    if (d.isNegative) return '0:00';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

class _Art extends StatelessWidget {
  const _Art({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 60,
        height: 60,
        child: url == null || url!.isEmpty
            // The app's own mark, which is also what Discord falls back to
            // when a title has no poster — so the placeholder is honest about
            // what would actually appear.
            ? ColoredBox(
                color: DiscordBrand.blurple,
                child: Center(child: DiscordBrand.mark(size: 26)),
              )
            : CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                placeholder: (_, _) =>
                    const ColoredBox(color: DiscordBrand.surfaceDeep),
                errorWidget: (_, _, _) => ColoredBox(
                  color: DiscordBrand.blurple,
                  child: Center(child: DiscordBrand.mark(size: 26)),
                ),
              ),
      ),
    );
  }
}

/// One line of the card, real or greyed.
class _Line extends StatelessWidget {
  const _Line({
    required this.text,
    required this.placeholder,
    this.strong = false,
  });

  final String? text;
  final String placeholder;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final live = text != null && text!.isNotEmpty;
    return Text(
      live ? text! : placeholder,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        // Dimmed and italic when it is standing in for something, so the card
        // never reads as a claim that this is what Discord is showing.
        color: Colors.white.withValues(alpha: live ? (strong ? 0.92 : 0.7) : 0.32),
        fontSize: 12.5,
        fontStyle: live ? FontStyle.normal : FontStyle.italic,
        fontWeight: strong && live ? FontWeight.w600 : FontWeight.w400,
      ),
    );
  }
}
