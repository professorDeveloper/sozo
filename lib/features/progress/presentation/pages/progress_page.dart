import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/achievements/domain/achievements.dart';
import 'package:soplay/features/progress/data/progress_service.dart';
import 'package:soplay/features/progress/domain/progress.dart';
import 'package:soplay/features/progress/presentation/widgets/level_ring.dart';
import 'package:soplay/features/progress/presentation/widgets/user_badge_line.dart';
import 'package:soplay/features/streak/presentation/widgets/streak_badge.dart';

/// The level, how it was earned, and the locker of what it unlocks.
class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  final ProgressService _service = getIt<ProgressService>();
  bool _loading = true;
  String? _saving;

  @override
  void initState() {
    super.initState();
    _service.state.addListener(_onChange);
    _service.refresh().whenComplete(() {
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _retry() async {
    setState(() => _loading = true);
    await _service.refresh();
    if (mounted) setState(() => _loading = false);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _service.state.removeListener(_onChange);
    super.dispose();
  }

  Future<void> _equip(CosmeticItem item, bool equipped) async {
    if (_saving != null) return;
    setState(() => _saving = '${item.slot.name}:${item.id}');
    try {
      await _service.equip(item.slot, equipped ? null : item.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('achievements.save_failed'.tr())),
          );
      }
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = _service.state.value;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: Text('progress.title'.tr()),
        actions: const [StreakBadge(), SizedBox(width: 8)],
      ),
      body: view == null
          ? Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.cloud_off_rounded,
                            size: 40,
                            color: AppColors.textHint,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'progress.unavailable'.tr(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextButton(
                            autofocus: true,
                            onPressed: _retry,
                            child: Text('general.retry'.tr()),
                          ),
                        ],
                      ),
                    ),
            )
          : RefreshIndicator(
              onRefresh: _service.refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _LevelCard(view: view),
                  const SizedBox(height: 16),
                  _SectionTitle('progress.how_to_earn'.tr()),
                  const _Rules(),
                  if (view.recent.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _SectionTitle('progress.recent'.tr()),
                    _Recent(gains: view.recent.take(8).toList()),
                  ],
                  const SizedBox(height: 16),
                  _SectionTitle('progress.locker'.tr()),
                  for (final slot in CosmeticSlot.values)
                    _LockerSlot(
                      slot: slot,
                      view: view,
                      saving: _saving,
                      onTap: _equip,
                    ),
                ],
              ),
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

BoxDecoration _card() => BoxDecoration(
  color: AppColors.surface,
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 0.5),
);

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.view});

  final ProgressView view;

  @override
  Widget build(BuildContext context) {
    final p = view.progress;
    final user = getIt<HiveService>().getUser();
    final display = user?.displayName?.trim();
    final name = display != null && display.isNotEmpty
        ? display
        : user?.displayIdentifier ?? '';
    final photo = user?.photoURL;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _card(),
      child: Column(
        children: [
          Row(
            children: [
              LevelRing(level: p.level, fraction: p.fraction, size: 112),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'progress.xp_total'.tr(args: ['${p.xp}']),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'progress.to_next'.tr(
                        args: ['${p.toNext}', '${p.level + 1}'],
                      ),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: view.watchCap <= 0
                            ? 0.0
                            : (view.watchXpToday / view.watchCap).clamp(
                                0.0,
                                1.0,
                              ),
                        minHeight: 5,
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'progress.watch_today'.tr(
                        args: ['${view.watchXpToday}', '${view.watchCap}'],
                      ),
                      style: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (name.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                FramedAvatar(
                  size: 40,
                  frame: view.frame,
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.surfaceVariant,
                    backgroundImage: photo != null && photo.isNotEmpty
                        ? NetworkImage(photo)
                        : null,
                    child: photo != null && photo.isNotEmpty
                        ? null
                        : Text(name.characters.first.toUpperCase()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: UserBadgeLine(
                    name: name,
                    decoration: view.decoration,
                    showTitle: true,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Rules extends StatelessWidget {
  const _Rules();

  @override
  Widget build(BuildContext context) {
    final rules = [
      (Icons.play_circle_outline_rounded, 'progress.rule_watch'.tr()),
      (Icons.chat_bubble_outline_rounded, 'progress.rule_comment'.tr()),
      (Icons.favorite_border_rounded, 'progress.rule_like'.tr()),
      (Icons.local_fire_department_rounded, 'progress.rule_streak'.tr()),
      (Icons.emoji_events_outlined, 'progress.rule_achievement'.tr()),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: _card(),
      child: Column(
        children: [
          for (final (icon, text) in rules)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: AppColors.primaryLight),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _reasonKey(String reason) => switch (reason) {
  'watch' => 'progress.reason_watch',
  'comment' => 'progress.reason_comment',
  'like' => 'progress.reason_like',
  'streak' => 'progress.reason_streak',
  'achievement' => 'progress.reason_achievement',
  _ => 'progress.reason_other',
};

class _Recent extends StatelessWidget {
  const _Recent({required this.gains});

  final List<XpGain> gains;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: _card(),
      child: Column(
        children: [
          for (final g in gains)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _reasonKey(g.reason).tr(),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  if (g.at != null)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 10),
                      child: Text(
                        DateFormat.MMMd(
                          context.locale.toString(),
                        ).format(g.at!),
                        style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  Text(
                    'progress.xp_gain'.tr(args: ['${g.xp}']),
                    style: TextStyle(
                      color: AppColors.primaryLight,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _slotKey(CosmeticSlot slot) => switch (slot) {
  CosmeticSlot.frame => 'progress.slot_frame',
  CosmeticSlot.title => 'progress.slot_title',
  CosmeticSlot.nameColor => 'progress.slot_color',
};

/// How to get a locked item: a level, or a badge at a tier.
String unlockHint(CosmeticItem item) {
  final badge = item.badge;
  if (item.level != null || badge == null) {
    return 'progress.unlock_level'.tr(args: ['${item.level ?? 0}']);
  }
  final def = AchievementDef.of(badge);
  final name = def.nameKey.tr();
  if (def.isSingle) return 'progress.unlock_badge'.tr(args: [name]);
  return 'progress.unlock_badge'.tr(
    args: ['$name · ${MedalTier.ofLevel(item.tier).labelKey.tr()}'],
  );
}

class _LockerSlot extends StatelessWidget {
  const _LockerSlot({
    required this.slot,
    required this.view,
    required this.saving,
    required this.onTap,
  });

  final CosmeticSlot slot;
  final ProgressView view;
  final String? saving;
  final Future<void> Function(CosmeticItem item, bool equipped) onTap;

  @override
  Widget build(BuildContext context) {
    final items = view
        .slot(slot)
        .where((c) => Cosmetics.isKnown(slot, c.id))
        .toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final current = view.equipped(slot);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: _card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
              child: Text(
                _slotKey(slot).tr(),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in items)
                  _LockerItem(
                    item: item,
                    equipped: current == item.id,
                    busy: saving == '${slot.name}:${item.id}',
                    onTap: item.unlocked
                        ? () => onTap(item, current == item.id)
                        : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LockerItem extends StatelessWidget {
  const _LockerItem({
    required this.item,
    required this.equipped,
    required this.busy,
    required this.onTap,
  });

  final CosmeticItem item;
  final bool equipped;
  final bool busy;
  final VoidCallback? onTap;

  Widget _preview() {
    switch (item.slot) {
      case CosmeticSlot.frame:
        return FramedAvatar(
          size: 34,
          frame: item.id,
          child: CircleAvatar(
            radius: 17,
            backgroundColor: AppColors.surfaceVariant,
            child: const Icon(
              Icons.person_rounded,
              size: 20,
              color: AppColors.textHint,
            ),
          ),
        );
      case CosmeticSlot.nameColor:
        return Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: Cosmetics.nameColor(item.id),
            shape: BoxShape.circle,
          ),
        );
      case CosmeticSlot.title:
        return const Icon(
          Icons.workspace_premium_outlined,
          size: 24,
          color: AppColors.textSecondary,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = !item.unlocked;
    final label = Cosmetics.label(item.slot, item.id);
    return Tooltip(
      message: locked ? unlockHint(item) : label,
      child: Semantics(
        selected: equipped,
        child: HoverTap(
          onTap: onTap,
          borderRadius: 12,
          scale: 1.03,
          child: Container(
            width: 100,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            decoration: BoxDecoration(
              color: equipped
                  ? AppColors.primary.withValues(alpha: 0.14)
                  : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: equipped
                    ? AppColors.primary.withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.06),
              ),
            ),
            child: Opacity(
              opacity: locked ? 0.5 : 1,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 44,
                    child: Center(
                      child: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : _preview(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: item.slot == CosmeticSlot.nameColor
                          ? Cosmetics.nameColor(item.id)
                          : AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (locked) ...[
                        const Icon(
                          Icons.lock_outline_rounded,
                          size: 11,
                          color: AppColors.textHint,
                        ),
                        const SizedBox(width: 3),
                      ],
                      Flexible(
                        child: Text(
                          locked
                              ? unlockHint(item)
                              : equipped
                              ? 'progress.equipped'.tr()
                              : 'progress.equip'.tr(),
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textHint,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
