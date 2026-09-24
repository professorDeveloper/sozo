import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/profiles/data/profile_session.dart';
import 'package:soplay/features/profiles/presentation/widgets/profile_avatar.dart';

/// Profile hub row: who is watching, and the way to switch or manage.
class ActiveProfileCard extends StatefulWidget {
  const ActiveProfileCard({super.key});

  @override
  State<ActiveProfileCard> createState() => _ActiveProfileCardState();
}

class _ActiveProfileCardState extends State<ActiveProfileCard> {
  final ProfileSession _session = getIt<ProfileSession>();

  @override
  void initState() {
    super.initState();
    _session.addListener(_changed);
    if (!_session.loaded) _session.refresh();
  }

  @override
  void dispose() {
    _session.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final active = _session.active;
    final count = _session.profiles.length;
    final several = count > 1;
    final String title;
    final String subtitle;
    if (active == null || !several) {
      title = 'profiles.title'.tr();
      subtitle = 'profiles.card_single'.tr();
    } else {
      title = active.name;
      subtitle = active.isKids
          ? 'profiles.kids'.tr()
          : 'profiles.count'.tr(args: ['$count']);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.push(several ? '/profiles' : '/profiles/manage'),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.05),
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                if (active != null && several)
                  ProfileAvatar.of(active, size: 44, showLock: false)
                else
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.people_alt_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (several)
                  TextButton.icon(
                    onPressed: () => context.push('/profiles'),
                    icon: const Icon(Icons.switch_account_rounded, size: 18),
                    label: Text('profiles.switch_short'.tr()),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                    ),
                  )
                else
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textHint,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
