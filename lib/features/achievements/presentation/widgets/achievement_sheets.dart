import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/achievements/data/achievements_service.dart';
import 'package:soplay/features/achievements/domain/achievements.dart';
import 'package:soplay/features/achievements/presentation/widgets/achievement_medal.dart';
import 'package:soplay/features/achievements/presentation/widgets/medal_viewer.dart';

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

/// A badge held up for a closer look — see [showMedalViewer].
Future<void> openAchievement(
  BuildContext context, {
  required AchievementsView view,
  required String id,
}) => showMedalViewer(context, id: id, view: view);

/// How many badges a profile can put on show; the server holds the same.
const int showcaseMax = 6;

/// Picks up to [showcaseMax] earned badges to show beside the profile's name.
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
      if (_picked.length >= showcaseMax) _picked.removeAt(0);
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
