import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:share_plus/share_plus.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/achievements/domain/achievements.dart';
import 'package:soplay/features/achievements/presentation/widgets/achievement_medal.dart';

/// A badge held up to the light: the medal large, turned by a finger or by
/// tilting the phone, its shadow sliding across the floor beneath it.
///
/// Opened from any medal — one's own page, a friend's profile, the feed. A
/// family can be stepped through tier by tier, each one earned or not.
Future<void> showMedalViewer(
  BuildContext context, {
  required String id,
  AchievementsView? view,
  int? tier,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Badge',
    barrierColor: Colors.black.withValues(alpha: 0.92),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, _, _) => _MedalViewer(id: id, view: view, tier: tier),
    transitionBuilder: (_, anim, _, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween(
          begin: 0.94,
          end: 1.0,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  );
}

class _MedalViewer extends StatefulWidget {
  const _MedalViewer({required this.id, this.view, this.tier});

  final String id;
  final AchievementsView? view;
  final int? tier;

  @override
  State<_MedalViewer> createState() => _MedalViewerState();
}

class _MedalViewerState extends State<_MedalViewer>
    with TickerProviderStateMixin {
  late final AchievementFamily? _family = widget.view?.family(widget.id);
  late final AchievementSingle? _single = widget.view?.single(widget.id);
  late final AchievementDef _def = AchievementDef.of(widget.id);

  /// The family tier on show, 1-based; the highest earned to begin with.
  late int _shown =
      widget.tier ??
      (_family == null
          ? 1
          : _family.tier.clamp(1, math.max(1, _family.tiers.length)));

  // Where the medal points: the finger when there is one, else the phone's
  // own tilt, else a slow idle sway so it never sits dead still.
  Offset _drag = Offset.zero;
  Offset _gyro = Offset.zero;
  bool _dragging = false;
  Offset _released = Offset.zero;
  late final AnimationController _return = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final Ticker _clock = createTicker((d) {
    _t = d.inMicroseconds / 1e6;
    if (mounted) setState(() {});
  });
  double _t = 0;

  /// A double tap flips the medal like a coin.
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  StreamSubscription<AccelerometerEvent>? _sensor;

  @override
  void initState() {
    super.initState();
    _clock.start();
    try {
      _sensor =
          accelerometerEventStream(
            samplingPeriod: SensorInterval.uiInterval,
          ).listen(
            (e) {
              // Gravity along x and y, as the phone leans; smoothed so a hand's
              // tremor does not shake the medal.
              final target = Offset(
                (-e.x / 6).clamp(-1.0, 1.0),
                ((e.y - 6.5) / 6).clamp(-1.0, 1.0),
              );
              _gyro = Offset.lerp(_gyro, target, 0.12)!;
            },
            onError: (_) {},
            cancelOnError: true,
          );
    } catch (_) {}
  }

  @override
  void dispose() {
    _sensor?.cancel();
    _clock.dispose();
    _return.dispose();
    _flip.dispose();
    super.dispose();
  }

  Offset get _tilt {
    if (_dragging) return _drag;
    final back = Curves.easeOutBack.transform(_return.value);
    final settled = Offset.lerp(_released, Offset.zero, back)!;
    final idle = Offset(math.sin(_t * 0.9) * 0.22, math.cos(_t * 0.7) * 0.14);
    final ease = _return.isAnimating ? back : 1.0;
    return settled + (_gyro + idle) * ease;
  }

  MedalTier get _medal {
    final family = _family;
    if (family != null) {
      return _shown <= family.tier
          ? MedalTier.ofLevel(_shown)
          : MedalTier.locked;
    }
    final single = _single;
    if (single != null) return single.medal;
    return MedalTier.gold;
  }

  bool get _earned => _medal != MedalTier.locked;

  void _onPan(Offset local, Size box) {
    setState(() {
      _dragging = true;
      _drag = Offset(
        ((local.dx / box.width) * 2 - 1).clamp(-1.2, 1.2),
        ((local.dy / box.height) * 2 - 1).clamp(-1.2, 1.2),
      );
    });
  }

  void _onRelease() {
    _released = _drag;
    _dragging = false;
    _return.forward(from: 0);
  }

  String get _headline => _def.nameKey.tr();

  String get _requirement {
    final family = _family;
    if (family != null && family.tiers.isNotEmpty) {
      final need = family.tiers[_shown - 1];
      return _def.unitKey.tr(
        args: [NumberFormat.decimalPattern().format(need)],
      );
    }
    return _def.unitKey.tr();
  }

  DateTime? get _earnedAt {
    final family = _family;
    if (family != null) {
      final i = _shown - 1;
      return i < family.unlockedAt.length ? family.unlockedAt[i] : null;
    }
    return _single?.at;
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final size = math.min(screen.width * 0.62, 280.0);
    final tilt = _tilt;
    final flip = Curves.easeInOutCubic.transform(_flip.value) * math.pi * 2;
    final medal = _medal;
    final color = medal.labelColor;
    final earnedAt = _earnedAt;

    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Stack(
          children: [
            // The medal's own light on the dark behind it.
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _BackdropPainter(
                    color: color,
                    earned: _earned,
                    t: _t,
                    sparks: medal == MedalTier.ember || medal == MedalTier.gold,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 48,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: size * 1.3,
                      height: size * 1.32,
                      child: LayoutBuilder(
                        builder: (context, box) => GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanDown: (d) => _onPan(
                            d.localPosition,
                            Size(box.maxWidth, box.maxHeight),
                          ),
                          onPanUpdate: (d) => _onPan(
                            d.localPosition,
                            Size(box.maxWidth, box.maxHeight),
                          ),
                          onPanEnd: (_) => _onRelease(),
                          onPanCancel: _onRelease,
                          onDoubleTap: () => _flip.forward(from: 0),
                          child: Stack(
                            alignment: Alignment.topCenter,
                            children: [
                              // The floor shadow: it slides opposite the tilt
                              // and stretches as the medal leans away.
                              Positioned(
                                bottom: 0,
                                child: Transform.translate(
                                  offset: Offset(-tilt.dx * size * 0.16, 0),
                                  child: Container(
                                    width:
                                        size *
                                        (0.72 + tilt.dx.abs() * 0.12) *
                                        (0.75 + 0.25 * math.cos(flip).abs()),
                                    height: size * (0.11 + tilt.dy * 0.03),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(size),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.75,
                                          ),
                                          blurRadius: size * 0.12,
                                          spreadRadius: size * 0.02,
                                        ),
                                        if (_earned)
                                          BoxShadow(
                                            color: color.withValues(
                                              alpha: 0.18,
                                            ),
                                            blurRadius: size * 0.2,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              // The medal floats, turned in perspective.
                              Positioned(
                                top: size * 0.04 + math.sin(_t * 1.4) * 4,
                                child: AnimatedBuilder(
                                  animation: _flip,
                                  builder: (_, _) => Transform(
                                    alignment: Alignment.center,
                                    transform: Matrix4.identity()
                                      ..setEntry(3, 2, 0.0012)
                                      ..rotateX(-tilt.dy * 0.38)
                                      ..rotateY(tilt.dx * 0.46 + flip),
                                    child: AchievementMedal(
                                      tier: medal,
                                      icon: _def.icon,
                                      size: size,
                                      showBack:
                                          math.cos(tilt.dx * 0.46 + flip) < 0,
                                      light: Offset(
                                        tilt.dx + math.sin(flip) * 0.8,
                                        tilt.dy,
                                      ),
                                      progress: medal == MedalTier.locked
                                          ? _lockedProgress
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      _headline,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _family == null
                            ? (_earned
                                  ? 'achievements.rare'.tr()
                                  : 'achievements.not_yet'.tr())
                            : MedalTier.ofLevel(_shown).labelKey.tr(),
                        style: TextStyle(
                          color: _earned ? color : AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _requirement,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      earnedAt != null
                          ? 'achievements.earned_on'.tr(
                              args: [
                                DateFormat.yMMMd(
                                  context.locale.toString(),
                                ).format(earnedAt),
                              ],
                            )
                          : _earned
                          ? ''
                          : 'achievements.not_yet'.tr(),
                      style: TextStyle(
                        color: AppColors.textHint,
                        fontSize: 12.5,
                      ),
                    ),
                    if (_family != null && _family.tiers.length > 1) ...[
                      const SizedBox(height: 20),
                      _TierStrip(
                        id: widget.id,
                        family: _family,
                        shown: _shown,
                        onPick: (t) => setState(() => _shown = t),
                      ),
                    ],
                    if (_earned) ...[
                      const SizedBox(height: 20),
                      TextButton.icon(
                        onPressed: () => Share.share(
                          'achievements.share_text'.tr(
                            args: [
                              _family == null
                                  ? _headline
                                  : '$_headline · ${MedalTier.ofLevel(_shown).labelKey.tr()}',
                            ],
                          ),
                        ),
                        icon: const Icon(Icons.ios_share_rounded, size: 18),
                        label: Text('achievements.share'.tr()),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'achievements.viewer_hint'.tr(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textHint,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A locked tier: how far along toward it, when that is known.
  double? get _lockedProgress {
    final family = _family;
    if (family != null) {
      final value = family.value;
      if (value == null) return null;
      return (value / family.tiers[_shown - 1]).clamp(0.0, 1.0);
    }
    final single = _single;
    if (single != null && single.value != null) {
      return (single.value! / single.need).clamp(0.0, 1.0);
    }
    return null;
  }
}

/// The family's tiers as small medals, to step through.
class _TierStrip extends StatelessWidget {
  const _TierStrip({
    required this.id,
    required this.family,
    required this.shown,
    required this.onPick,
  });

  final String id;
  final AchievementFamily family;
  final int shown;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= family.tiers.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: GestureDetector(
              onTap: () => onPick(i),
              child: AnimatedScale(
                scale: i == shown ? 1.15 : 0.9,
                duration: const Duration(milliseconds: 200),
                child: AnimatedOpacity(
                  opacity: i == shown ? 1 : 0.6,
                  duration: const Duration(milliseconds: 200),
                  child: AchievementBadge(
                    id: id,
                    tier: i <= family.tier
                        ? MedalTier.ofLevel(i)
                        : MedalTier.locked,
                    size: 44,
                    glow: false,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A glow in the medal's colour behind it, breathing, and — for gold and
/// ember — sparks drifting up.
class _BackdropPainter extends CustomPainter {
  _BackdropPainter({
    required this.color,
    required this.earned,
    required this.t,
    required this.sparks,
  });

  final Color color;
  final bool earned;
  final double t;
  final bool sparks;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.36);
    final breathe = 0.85 + 0.15 * math.sin(t * 1.2);
    final r = size.width * 0.75 * breathe;
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: earned ? 0.30 : 0.10),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );
    if (!sparks || !earned) return;
    final paint = Paint();
    for (var i = 0; i < 26; i++) {
      final seed = i * 37.0;
      final speed = 18 + (i % 5) * 7.0;
      final x = size.width * ((seed * 0.618) % 1) + math.sin(t * 0.8 + i) * 12;
      final y = size.height - ((t * speed + seed * 9) % (size.height * 0.9));
      final life = 1 - (size.height - y) / (size.height * 0.9);
      final radius = 1.2 + (i % 3) * 0.8;
      paint.color = color.withValues(alpha: 0.55 * life.clamp(0.0, 1.0));
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter old) =>
      old.t != t || old.color != color || old.earned != earned;
}
