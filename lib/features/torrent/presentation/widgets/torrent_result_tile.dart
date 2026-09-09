import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/torrent/domain/entities/torrent_result.dart';

/// One search result.
///
/// The layout answers, in the order a user actually scans them: *can I play
/// this* (swarm health), *what is it* (title), *what quality* (badges), *from
/// where and how big* (footer). Health leads because it is the only property
/// that can make the row useless — a beautiful 1080p dual-audio remux with zero
/// seeders is not a choice, it is a dead end.
class TorrentResultTile extends StatelessWidget {
  const TorrentResultTile({
    super.key,
    required this.result,
    required this.onTap,
    this.onLongPress,
  });

  final TorrentResult result;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  Color get _healthColor => switch (result.health) {
        SwarmHealth.good => AppColors.success,
        SwarmHealth.fair => AppColors.rating,
        SwarmHealth.poor => AppColors.errorLight,
        SwarmHealth.dead => AppColors.error,
        // Grey, not red: Tokyo Toshokan simply does not report swarm size, and
        // painting every one of its rows as dead would be a lie.
        SwarmHealth.unknown => AppColors.textHint,
      };

  @override
  Widget build(BuildContext context) {
    final dead = result.health == SwarmHealth.dead;

    return InkWell(
      onTap: dead ? null : onTap,
      onLongPress: onLongPress,
      child: Opacity(
        // Dead torrents stay visible but are clearly out of play: hiding them
        // outright would leave users searching for a release that "should" be
        // there and wondering why it is not.
        opacity: dead ? 0.45 : 1,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 3,
                height: 38,
                margin: const EdgeInsetsDirectional.only(top: 2, end: 12),
                decoration: BoxDecoration(
                  color: _healthColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _title(),
                    if (result.release.badges.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      _badges(),
                    ],
                    const SizedBox(height: 7),
                    _footer(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _title() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (result.trusted)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 2, end: 5),
            child: Tooltip(
              message: 'torrent.trusted'.tr(),
              child: Icon(
                Icons.verified_rounded,
                size: 14,
                color: AppColors.success,
              ),
            ),
          ),
        if (result.remake)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 2, end: 5),
            child: Tooltip(
              message: 'torrent.remake'.tr(),
              child: Icon(
                Icons.replay_rounded,
                size: 14,
                color: AppColors.errorLight,
              ),
            ),
          ),
        Expanded(
          child: Text(
            result.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13.5,
              height: 1.3,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _badges() {
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (final badge in result.release.badges)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              badge,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
      ],
    );
  }

  Widget _footer() {
    final seeders = result.seeders;
    final size = result.displaySize;

    return DefaultTextStyle(
      style: TextStyle(color: AppColors.textHint, fontSize: 11.5),
      child: Row(
        children: [
          Icon(Icons.arrow_upward_rounded, size: 12, color: _healthColor),
          const SizedBox(width: 2),
          Text(
            // "?" rather than "0": the tracker not saying is a different fact
            // from it saying nobody is seeding.
            seeders?.toString() ?? '?',
            style: TextStyle(
              color: _healthColor,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (result.leechers != null) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_downward_rounded,
              size: 12,
              color: AppColors.textHint,
            ),
            const SizedBox(width: 2),
            Text('${result.leechers}'),
          ],
          if (size != null) ...[
            _dot(),
            Text(size),
          ],
          const Spacer(),
          Text(
            result.indexerName,
            style: TextStyle(
              color: AppColors.textHint,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text('·', style: TextStyle(color: AppColors.textHint)),
      );
}
