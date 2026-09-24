import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/achievements/domain/achievements.dart';
import 'package:soplay/features/achievements/presentation/widgets/achievement_medal.dart';

const Color _ember = Color(0xFFFFA94D);
const Color _emberDeep = Color(0xFFEF7A35);
const Color _emberSoft = Color(0xFFFFC078);

/// "You earned a badge": the medal struck in, confetti, and what comes next.
///
/// Shows the one that matters most — the streak before anything else, then
/// the highest tier — and the rest as a row under it, so a first sync that
/// earns five badges is one celebration, not five dialogs in a row.
class AchievementUnlockedDialog extends StatefulWidget {
  const AchievementUnlockedDialog({
    super.key,
    required this.unlocks,
    this.view,
    this.onSeeAll,
  });

  final List<AchievementUnlock> unlocks;

  /// For the progress to the next tier; the dialog works without it.
  final AchievementsView? view;
  final VoidCallback? onSeeAll;

  static Future<void> show(
    BuildContext context,
    List<AchievementUnlock> unlocks, {
    AchievementsView? view,
    VoidCallback? onSeeAll,
  }) {
    if (unlocks.isEmpty) return Future.value();
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Achievement',
      barrierColor: Colors.black.withValues(alpha: 0.8),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, _, _) => AchievementUnlockedDialog(
        unlocks: unlocks,
        view: view,
        onSeeAll: onSeeAll,
      ),
      transitionBuilder: (_, anim, _, child) {
        final t = Curves.easeOutCubic.transform(anim.value.clamp(0, 1));
        return Opacity(
          opacity: anim.value,
          child: Transform.scale(scale: 0.9 + 0.1 * t, child: child),
        );
      },
    );
  }

  /// The order unlocks are shown in: the streak first, then by tier.
  static List<AchievementUnlock> ranked(List<AchievementUnlock> unlocks) {
    // Only the highest tier of each family: passing bronze and silver on the
    // way to gold in one sync is one gold, not three badges.
    final best = <String, AchievementUnlock>{};
    for (final u in unlocks) {
      final had = best[u.id];
      if (had == null || u.tier > had.tier) best[u.id] = u;
    }
    int weight(AchievementUnlock u) {
      if (u.id == 'streak') return 100 + u.tier;
      if (u.isSingle) return 10 + (u.id == 'iron_will' ? 50 : 3);
      return u.tier * 10;
    }

    return best.values.toList()..sort((a, b) => weight(b).compareTo(weight(a)));
  }

  @override
  State<AchievementUnlockedDialog> createState() =>
      _AchievementUnlockedDialogState();
}

class _AchievementUnlockedDialogState extends State<AchievementUnlockedDialog>
    with TickerProviderStateMixin {
  late final AnimationController _strike = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();
  late final AnimationController _confetti = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..forward();

  late final List<AchievementUnlock> _ranked = AchievementUnlockedDialog.ranked(
    widget.unlocks,
  );

  @override
  void dispose() {
    _strike.dispose();
    _confetti.dispose();
    super.dispose();
  }

  AchievementUnlock get _hero => _ranked.first;

  MedalTier _medalOf(AchievementUnlock u) => u.isSingle
      ? (widget.view?.single(u.id)?.rarity ?? AchievementDef.of(u.id).rarity)
      : MedalTier.ofLevel(u.tier);

  String _headline(AchievementUnlock u) {
    final name = AchievementDef.of(u.id).nameKey.tr();
    if (u.isSingle) return name;
    return '$name · ${MedalTier.ofLevel(u.tier).labelKey.tr()}';
  }

  /// What was done to earn it, in words: "500 episodes watched".
  String _body(AchievementUnlock u) {
    final def = AchievementDef.of(u.id);
    if (u.isSingle) return def.unitKey.tr();
    final family = widget.view?.family(u.id);
    final tiers = family?.tiers ?? const <int>[];
    final reached = u.tier - 1 < tiers.length && u.tier > 0
        ? tiers[u.tier - 1]
        : null;
    if (reached == null) return '';
    return def.unitKey.tr(args: ['$reached']);
  }

  Future<void> _share() async {
    await Share.share('achievements.share_text'.tr(args: [_headline(_hero)]));
  }

  @override
  Widget build(BuildContext context) {
    final hero = _hero;
    final medal = _medalOf(hero);
    final family = hero.isSingle ? null : widget.view?.family(hero.id);
    final others = _ranked.skip(1).take(4).toList();
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _confetti,
                    builder: (_, _) =>
                        CustomPaint(painter: _ConfettiPainter(_confetti.value)),
                  ),
                ),
              ),
              Container(
                constraints: const BoxConstraints(maxWidth: 360),
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.surface, AppColors.background],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _ember.withValues(alpha: 0.22),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _emberDeep.withValues(alpha: 0.16),
                      blurRadius: 34,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'achievements.new_badge'.tr().toUpperCase(),
                      style: const TextStyle(
                        color: _ember,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.8,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _StruckMedal(
                      animation: _strike,
                      child: AchievementBadge(
                        id: hero.id,
                        tier: medal,
                        size: 128,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      AchievementDef.of(hero.id).nameKey.tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: medal.labelColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        hero.isSingle
                            ? 'achievements.rare'.tr()
                            : 'achievements.tier_n'.tr(
                                args: [medal.labelKey.tr()],
                              ),
                        style: TextStyle(
                          color: medal.labelColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (_body(hero).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        _body(hero),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14.5,
                          height: 1.45,
                        ),
                      ),
                    ],
                    if (family != null && !family.isMaxed) ...[
                      const SizedBox(height: 14),
                      _NextTier(family: family),
                    ],
                    if (others.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _AlsoEarned(
                        others: others,
                        medalOf: _medalOf,
                        extra: _ranked.length - 1 - others.length,
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _share,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(48),
                              side: BorderSide(color: AppColors.border),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.ios_share_rounded, size: 18),
                            label: Text('achievements.share'.tr()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _EmberButton(
                            label: 'achievements.great'.tr(),
                            onTap: () => Navigator.of(context).maybePop(),
                          ),
                        ),
                      ],
                    ),
                    if (widget.onSeeAll != null) ...[
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).maybePop();
                          widget.onSeeAll!();
                        },
                        child: Text(
                          'achievements.see_all'.tr(),
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The medal arriving: it drops in slightly large and settles, then a band
/// of light crosses its face once.
class _StruckMedal extends StatelessWidget {
  const _StruckMedal({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (_, child) {
        final v = animation.value;
        final settle = Curves.easeOutBack.transform((v / 0.55).clamp(0.0, 1.0));
        final sweep = ((v - 0.45) / 0.55).clamp(0.0, 1.0);
        return Transform.scale(
          scale: 0.6 + 0.4 * settle,
          child: Opacity(
            opacity: (v / 0.25).clamp(0.0, 1.0),
            child: ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (rect) => LinearGradient(
                begin: const Alignment(-1, -1),
                end: const Alignment(1, 1),
                colors: [
                  Colors.white.withValues(alpha: 0),
                  Colors.white.withValues(
                    alpha: sweep > 0 && sweep < 1 ? 0.55 : 0,
                  ),
                  Colors.white.withValues(alpha: 0),
                ],
                stops: [
                  (sweep * 1.4 - 0.4).clamp(0.0, 1.0),
                  (sweep * 1.4 - 0.2).clamp(0.0, 1.0),
                  (sweep * 1.4).clamp(0.0, 1.0),
                ],
              ).createShader(rect),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _NextTier extends StatelessWidget {
  const _NextTier({required this.family});

  final AchievementFamily family;

  @override
  Widget build(BuildContext context) {
    final next = MedalTier.ofLevel(family.tier + 1);
    final target = family.tiers[family.tier];
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: family.progress,
            minHeight: 6,
            backgroundColor: AppColors.border,
            valueColor: const AlwaysStoppedAnimation(_emberSoft),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'achievements.next_at'.tr(
            args: [
              next.labelKey.tr(),
              AchievementDef.of(family.id).unitKey.tr(args: ['$target']),
            ],
          ),
          style: TextStyle(color: AppColors.textHint, fontSize: 12),
        ),
      ],
    );
  }
}

class _AlsoEarned extends StatelessWidget {
  const _AlsoEarned({
    required this.others,
    required this.medalOf,
    required this.extra,
  });

  final List<AchievementUnlock> others;
  final MedalTier Function(AchievementUnlock) medalOf;
  final int extra;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'achievements.also_earned'.tr(),
          style: TextStyle(color: AppColors.textHint, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final u in others)
              Tooltip(
                message: AchievementDef.of(u.id).nameKey.tr(),
                child: AchievementBadge(
                  id: u.id,
                  tier: medalOf(u),
                  size: 40,
                  glow: false,
                ),
              ),
            if (extra > 0)
              Text(
                '+$extra',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _EmberButton extends StatelessWidget {
  const _EmberButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_ember, _emberDeep]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF1A0A00),
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t);

  final double t;

  static const _colors = [
    _ember,
    _emberDeep,
    _emberSoft,
    Color(0xFFF4C443),
    Color(0xFFFF4D5E),
    Color(0xFF8FD4FF),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (t >= 1) return;
    final fade = t < 0.75 ? 1.0 : (1 - (t - 0.75) / 0.25);
    final paint = Paint();
    for (var i = 0; i < 46; i++) {
      final seed = i * 97.0;
      final x0 = (seed * 13) % size.width;
      final drift = math.sin(seed + t * 6) * 18;
      final fall = (t * (0.7 + (i % 5) * 0.12)) * size.height * 1.1;
      final y = -20 + fall + (i % 7) * 6.0 - size.height * 0.15;
      if (y < -24 || y > size.height + 24) continue;
      paint.color = _colors[i % _colors.length].withValues(alpha: 0.9 * fade);
      canvas.save();
      canvas.translate(x0 + drift, y);
      canvas.rotate(seed + t * (4 + i % 3));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 6, height: 10),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
