import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/app_buttons.dart';
import 'package:soplay/features/onboarding/data/library_import_service.dart';

/// A running import, shown as covers flying onto a shelf while the counts
/// tick up underneath.
class ImportShowcase extends StatefulWidget {
  const ImportShowcase({
    super.key,
    required this.source,
    required this.service,
    this.onFinished,
    this.onFailed,
    this.accent,
  });

  final ImportSource source;
  final LibraryImportService service;
  final ValueChanged<ImportProgress>? onFinished;
  final VoidCallback? onFailed;
  final Color? accent;

  @override
  State<ImportShowcase> createState() => _ImportShowcaseState();
}

class _ImportShowcaseState extends State<ImportShowcase> {
  static const _columns = 4;
  static const _rows = 3;
  static const _slots = _columns * _rows;

  final List<_Tile?> _tiles = List.filled(_slots, null);
  int _covers = 0;
  ImportProgress? _last;
  Object? _error;
  StreamSubscription<ImportProgress>? _sub;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _start() {
    _sub?.cancel();
    setState(() => _error = null);
    _sub = widget.service
        .run(widget.source)
        .listen(
          (p) {
            if (!mounted) return;
            setState(() {
              _last = p;
              final cover = p.cover;
              if (cover != null) {
                _tiles[_covers % _slots] = _Tile(cover, _covers);
                _covers++;
              }
            });
            if (p.finished) widget.onFinished?.call(p);
          },
          onError: (Object e) {
            if (!mounted) return;
            setState(() => _error = e);
            widget.onFailed?.call();
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent ?? AppColors.primary;
    final p = _last;
    final done = p?.finished ?? false;
    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 40,
            color: AppColors.textHint,
          ),
          const SizedBox(height: 10),
          Text(
            'onboarding.import_failed'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          AppSecondaryButton(
            label: 'onboarding.retry'.tr(),
            expand: false,
            onPressed: _start,
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            const gap = 8.0;
            final cellW = (box.maxWidth - gap * (_columns - 1)) / _columns;
            final cellH = cellW * 1.45;
            return SizedBox(
              height: cellH * _rows + gap * (_rows - 1),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < _slots; i++)
                    Positioned(
                      left: (i % _columns) * (cellW + gap),
                      top: (i ~/ _columns) * (cellH + gap),
                      width: cellW,
                      height: cellH,
                      child: _tiles[i] == null
                          ? const _EmptySlot()
                          : _FlyingTile(
                              key: ValueKey(_tiles[i]!.serial),
                              tile: _tiles[i]!,
                              from: _launchOffset(
                                _tiles[i]!.serial,
                                box.maxWidth,
                              ),
                            ),
                    ),
                  if (done)
                    Positioned.fill(
                      child: Center(child: _DoneBadge(color: accent)),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 18),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: p == null || p.total == 0
                ? (done ? 1 : null)
                : p.done / p.total,
            minHeight: 5,
            color: accent,
            backgroundColor: AppColors.surfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        Semantics(
          liveRegion: true,
          child: Row(
            children: [
              Expanded(
                child: _Count(
                  value: p?.followed ?? 0,
                  label: 'onboarding.import_following'.tr(),
                  color: accent,
                ),
              ),
              Expanded(
                child: _Count(
                  value: p?.listed ?? 0,
                  label: 'onboarding.import_my_list'.tr(),
                  color: accent,
                ),
              ),
            ],
          ),
        ),
        if (done && (p?.unmatched ?? 0) > 0) ...[
          const SizedBox(height: 8),
          Text(
            'onboarding.import_unmatched'.tr(args: ['${p!.unmatched}']),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textHint, fontSize: 12),
          ),
        ],
        if (done && p!.total > 0 && p.followed + p.listed == 0) ...[
          const SizedBox(height: 8),
          Text(
            'onboarding.import_already'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textHint, fontSize: 12),
          ),
        ],
      ],
    );
  }

  /// Where a cover starts its flight: off below the shelf, to one side or
  /// the other, so the shelf fills from a scatter rather than a queue.
  Offset _launchOffset(int serial, double width) {
    final r = math.Random(serial * 7919);
    return Offset((r.nextDouble() - 0.5) * width, 260 + r.nextDouble() * 120);
  }
}

class _Tile {
  const _Tile(this.cover, this.serial);

  final String cover;
  final int serial;
}

class _FlyingTile extends StatelessWidget {
  const _FlyingTile({super.key, required this.tile, required this.from});

  final _Tile tile;
  final Offset from;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final spin = (tile.serial.isEven ? 1 : -1) * 0.5;
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: tile.cover,
        fit: BoxFit.cover,
        memCacheWidth: 200,
        fadeInDuration: Duration.zero,
        placeholder: (_, _) => const ColoredBox(color: Color(0x22FFFFFF)),
        errorWidget: (_, _, _) => const ColoredBox(color: Color(0x22FFFFFF)),
      ),
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: still ? 150 : 700),
      curve: still ? Curves.linear : const Cubic(0.05, 0.7, 0.1, 1.0),
      builder: (context, t, child) {
        if (still) return Opacity(opacity: t, child: child);
        return Transform.translate(
          offset: from * (1 - t),
          child: Transform.rotate(
            angle: spin * (1 - t),
            child: Transform.scale(
              scale: 0.6 + 0.4 * t,
              child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
            ),
          ),
        );
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x80000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: image,
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: const Color(0x0DFFFFFF),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
    );
  }
}

class _DoneBadge extends StatelessWidget {
  const _DoneBadge({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Transform.scale(scale: t, child: child),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 30),
          ],
        ),
        child: const Icon(Icons.check_rounded, size: 40, color: Colors.white),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.value, required this.label, required this.color});

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(end: value.toDouble()),
          duration: const Duration(milliseconds: 400),
          builder: (context, v, _) => Text(
            '${v.round()}',
            style: TextStyle(
              color: color,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      ],
    );
  }
}

/// The same import, from Connections: a sheet that runs it and says how it
/// went.
Future<void> showLibraryImportSheet(
  BuildContext context,
  ImportSource source, {
  LibraryImportService? service,
}) {
  final svc = service ?? LibraryImportService.fromApp();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'onboarding.import_sheet_title'.tr(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 18),
                ImportShowcase(source: source, service: svc),
                const SizedBox(height: 16),
                AppPrimaryButton(
                  label: 'onboarding.done'.tr(),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
