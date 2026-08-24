import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/features/live_tv/data/live_tv_service.dart';

/// One channel, opened from a long press.
///
/// The card can only ever carry a name and a line of guide; this is where the
/// rest of it lives — what is on, what follows, the day ahead, and the two
/// things anybody wants to do with a channel.
Future<void> showChannelSheet({
  required BuildContext context,
  required LiveChannel channel,
  required bool favourite,
  required VoidCallback onPlay,
  required VoidCallback onToggleFavourite,
}) {
  return showAdaptiveModal<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => ChannelSheet(
      channel: channel,
      favourite: favourite,
      onPlay: onPlay,
      onToggleFavourite: onToggleFavourite,
    ),
  );
}

class ChannelSheet extends StatefulWidget {
  const ChannelSheet({
    super.key,
    required this.channel,
    required this.favourite,
    required this.onPlay,
    required this.onToggleFavourite,
  });

  final LiveChannel channel;
  final bool favourite;
  final VoidCallback onPlay;
  final VoidCallback onToggleFavourite;

  @override
  State<ChannelSheet> createState() => _ChannelSheetState();
}

class _ChannelSheetState extends State<ChannelSheet> {
  late bool _favourite;
  LiveSchedule? _schedule;
  bool _loadingSchedule = true;

  @override
  void initState() {
    super.initState();
    _favourite = widget.favourite;
    _loadSchedule();
  }

  /// Read once, here — a future created in `build()` is refetched every time
  /// the favourite button rebuilds this widget.
  Future<void> _loadSchedule() async {
    try {
      final schedule = await getIt<LiveTvService>().schedule(
        widget.channel.id,
        hours: 24,
      );
      if (!mounted) return;
      setState(() {
        _schedule = schedule;
        _loadingSchedule = false;
      });
    } catch (_) {
      if (!mounted) return;
      // A missing guide is not worth saying out loud twice; the empty branch
      // below already says it once, in the one place the user asked for it.
      setState(() => _loadingSchedule = false);
    }
  }

  void _play() {
    Navigator.of(context).pop();
    widget.onPlay();
  }

  void _toggleFavourite() {
    setState(() => _favourite = !_favourite);
    // The sheet stays open: favouriting is reversible and the guide underneath
    // is what the user came for.
    widget.onToggleFavourite();
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    final at = DateTime.now();
    final slot = channel.slotAt(at);
    final bar = _barValue(slot, at);
    final next = channel.next;

    return ConstrainedBox(
      // Both of showAdaptiveModal's dialog paths hand down an unbounded height
      // through their own scroll view; this is what makes it finite.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.78,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            6,
            18,
            MediaQuery.paddingOf(context).bottom + 14,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _identity(context, channel),
              if (slot != null) ..._nowBlock(slot, bar),
              if (next != null) ..._nextBlock(next),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _play,
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: Text('live_tv.watch'.tr()),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _toggleFavourite,
                icon: Icon(
                  _favourite ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 20,
                  color: _favourite
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
                label: Text(
                  _favourite
                      ? 'live_tv.favourite_remove'.tr()
                      : 'live_tv.favourite_add'.tr(),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Icon(
                    Icons.list_alt_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'live_tv.guide'.tr(),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _guide(at),
            ],
          ),
        ),
      ),
    );
  }

  Widget _identity(BuildContext context, LiveChannel channel) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: channel.logoUrl == null
              ? const Icon(
                  Icons.live_tv_rounded,
                  size: 22,
                  color: AppColors.textHint,
                )
              : CachedNetworkImage(
                  imageUrl: channel.logoUrl!,
                  fit: BoxFit.contain,
                  memCacheWidth: (32 * dpr).round(),
                  errorWidget: (_, _, _) => const Icon(
                    Icons.live_tv_rounded,
                    size: 22,
                    color: AppColors.textHint,
                  ),
                  placeholder: (_, _) => const SizedBox.shrink(),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                channel.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              if (channel.category.isNotEmpty) ...[
                const SizedBox(height: 3),
                // English, exactly as the line-up delivers it — the channel
                // names beside it are English too.
                Text(
                  channel.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _nowBlock(LiveProgramme slot, double? bar) {
    final detail = [
      slot.episodeLabel,
      slot.subtitle,
    ].where((value) => value.isNotEmpty).join(' · ');

    return [
      const SizedBox(height: 18),
      Text(
        'live_tv.now'.tr(),
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        slot.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
      ),
      if (detail.isNotEmpty) ...[
        const SizedBox(height: 3),
        Text(
          detail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
      if (slot.hasWindow) ...[
        const SizedBox(height: 8),
        Text(
          '${_hhmm(slot.start!)} – ${_hhmm(slot.stop!)}',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
      if (bar != null) ...[
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            // Explicitly full width: a column lays its children out loose, and
            // a track measured from its own fill is no track at all.
            width: double.infinity,
            height: 3,
            child: Container(
              color: AppColors.surfaceVariant,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: bar,
                heightFactor: 1,
                child: Container(color: AppColors.primary),
              ),
            ),
          ),
        ),
      ],
      if (slot.description.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(
          slot.description,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12.5,
            height: 1.45,
          ),
        ),
      ],
    ];
  }

  List<Widget> _nextBlock(LiveProgramme next) {
    return [
      const SizedBox(height: 16),
      Text(
        'live_tv.next'.tr(),
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
      const SizedBox(height: 5),
      Row(
        children: [
          if (next.hasWindow) ...[
            Text(
              _hhmm(next.start!),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 9),
          ],
          Expanded(
            child: Text(
              next.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ];
  }

  Widget _guide(DateTime at) {
    if (_loadingSchedule) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: List<Widget>.generate(
          3,
          (_) => const Padding(
            padding: EdgeInsets.symmetric(vertical: 9),
            child: ShimmerWrapper(
              child: Row(
                children: [
                  HomeSkeletonBox(width: 46, height: 10),
                  SizedBox(width: 10),
                  HomeSkeletonBox(width: 160, height: 10),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final schedule = _schedule;
    // The live row is already the NOW block above, and a row with no time has
    // nothing to put in its left column.
    final rows = schedule == null
        ? const <LiveProgramme>[]
        : schedule
              .from(at)
              .where((p) => p.start != null && !p.isLiveAt(at))
              .take(8)
              .toList(growable: false);

    if (rows.isEmpty) {
      return Text(
        'live_tv.no_guide'.tr(),
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: AppColors.divider),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 46,
                  child: Text(
                    _hhmm(rows[i].start!),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    rows[i].title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
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

/// Width factor for the NOW progress bar, or null when there is nothing honest
/// to draw. The sheet is open for seconds, so this is read once per build and
/// never ticked.
double? _barValue(LiveProgramme? slot, DateTime at) {
  if (slot == null || !slot.isBarWorthy) return null;
  final value = slot.progressAt(at);
  if (value <= 0) return null;
  return value < 0.02 ? 0.02 : value;
}

/// 24-hour, hand-formatted.
///
/// `intl` is not a declared dependency — it reaches the app only through
/// easy_localization's re-export — and `DateFormat.Hm` throws without locale
/// data initialised for uz. Digits need no translation either way.
String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
