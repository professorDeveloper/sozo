import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/achievements/data/achievements_service.dart';
import 'package:soplay/features/achievements/domain/achievements.dart';
import 'package:soplay/features/achievements/presentation/widgets/achievement_medal.dart';

Future<T?> _sheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => SafeArea(child: child),
  );
}

Widget _grabber() => Center(
  child: Container(
    width: 36,
    height: 4,
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: AppColors.textSecondary.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(2),
    ),
  ),
);

/// A family's or a single's details, whichever [id] is.
Future<void> openAchievement(
  BuildContext context, {
  required AchievementsView view,
  required String id,
}) {
  final family = view.family(id);
  if (family != null) return showFamilySheet(context, family: family);
  final single = view.single(id);
  if (single != null) return showSingleSheet(context, single: single);
  return Future.value();
}

/// The ladder: every tier of a family, what it takes, and when it came.
Future<void> showFamilySheet(
  BuildContext context, {
  required AchievementFamily family,
}) {
  final def = AchievementDef.of(family.id);
  final value = family.value;
  return _sheet(
    context,
    Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _grabber(),
          Row(
            children: [
              AchievementBadge(id: family.id, tier: family.medal, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      def.nameKey.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (value != null)
                      Text(
                        def.unitKey.tr(
                          args: [NumberFormat.decimalPattern().format(value)],
                        ),
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < family.tiers.length; i++)
            _LadderStep(
              id: family.id,
              tier: MedalTier.ofLevel(i + 1),
              earned: i < family.tier,
              requirement: def.unitKey.tr(
                args: [NumberFormat.decimalPattern().format(family.tiers[i])],
              ),
              at: i < family.unlockedAt.length ? family.unlockedAt[i] : null,
              current: i == family.tier,
              progress: i == family.tier ? family.progress : null,
            ),
          if (family.id == 'streak') ...[
            const SizedBox(height: 6),
            Text(
              'achievements.streak_note'.tr(),
              style: TextStyle(
                color: AppColors.textHint,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _LadderStep extends StatelessWidget {
  const _LadderStep({
    required this.id,
    required this.tier,
    required this.earned,
    required this.requirement,
    this.at,
    this.current = false,
    this.progress,
  });

  final String id;
  final MedalTier tier;
  final bool earned;
  final String requirement;
  final DateTime? at;
  final bool current;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          AchievementBadge(
            id: id,
            tier: earned ? tier : MedalTier.locked,
            size: 40,
            glow: false,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      tier.labelKey.tr(),
                      style: TextStyle(
                        color: earned
                            ? tier.labelColor
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        requirement,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
                if (earned && at != null)
                  Text(
                    'achievements.earned_on'.tr(
                      args: [
                        DateFormat.yMMMd(context.locale.toString()).format(at!),
                      ],
                    ),
                    style: TextStyle(color: AppColors.textHint, fontSize: 11.5),
                  )
                else if (current && progress != null) ...[
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: AppColors.border,
                      valueColor: AlwaysStoppedAnimation(tier.labelColor),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (earned)
            Icon(Icons.check_circle_rounded, color: tier.labelColor, size: 18),
        ],
      ),
    );
  }
}

Future<void> showSingleSheet(
  BuildContext context, {
  required AchievementSingle single,
}) {
  final def = AchievementDef.of(single.id);
  final value = single.value;
  return _sheet(
    context,
    Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _grabber(),
          AchievementBadge(id: single.id, tier: single.medal, size: 96),
          const SizedBox(height: 14),
          Text(
            def.nameKey.tr(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            def.unitKey.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 12),
          if (single.unlocked && single.at != null)
            Text(
              'achievements.earned_on'.tr(
                args: [
                  DateFormat.yMMMd(
                    context.locale.toString(),
                  ).format(single.at!),
                ],
              ),
              style: TextStyle(color: single.rarity.labelColor, fontSize: 13),
            )
          else if (!single.unlocked && value != null && single.need > 1) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (value / single.need).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation(single.rarity.labelColor),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$value / ${single.need}',
              style: TextStyle(color: AppColors.textHint, fontSize: 12),
            ),
          ] else if (!single.unlocked)
            Text(
              'achievements.not_yet'.tr(),
              style: TextStyle(color: AppColors.textHint, fontSize: 13),
            ),
        ],
      ),
    ),
  );
}

/// Picks up to three earned badges to show beside the profile's name.
Future<void> showShowcasePicker(
  BuildContext context, {
  required AchievementsView view,
}) {
  return _sheet(context, _ShowcasePicker(view: view));
}

class _ShowcasePicker extends StatefulWidget {
  const _ShowcasePicker({required this.view});

  final AchievementsView view;

  @override
  State<_ShowcasePicker> createState() => _ShowcasePickerState();
}

class _ShowcasePickerState extends State<_ShowcasePicker> {
  late final List<String> _picked = [...widget.view.showcase];
  bool _saving = false;

  void _toggle(String id) {
    setState(() {
      if (_picked.remove(id)) return;
      if (_picked.length >= 3) _picked.removeAt(0);
      _picked.add(id);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await getIt<AchievementsService>().setShowcase(_picked);
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('achievements.save_failed'.tr())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ids = widget.view.earnedIds;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _grabber(),
            Text(
              'achievements.showcase'.tr(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'achievements.showcase_hint'.tr(),
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                itemCount: ids.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 110,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.82,
                ),
                itemBuilder: (_, i) {
                  final id = ids[i];
                  final order = _picked.indexOf(id);
                  final on = order >= 0;
                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _toggle(id),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: on
                            ? const Color(0xFFFFA94D).withValues(alpha: 0.12)
                            : AppColors.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: on
                              ? const Color(0xFFFFA94D)
                              : Colors.transparent,
                          width: 1.4,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AchievementBadge(
                                id: id,
                                tier: widget.view.medalOf(id),
                                size: 50,
                                glow: false,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                AchievementDef.of(id).nameKey.tr(),
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  height: 1.15,
                                ),
                              ),
                            ],
                          ),
                          if (on)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: CircleAvatar(
                                radius: 10,
                                backgroundColor: const Color(0xFFFFA94D),
                                child: Text(
                                  '${order + 1}',
                                  style: const TextStyle(
                                    color: Color(0xFF1A0A00),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('achievements.save'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
