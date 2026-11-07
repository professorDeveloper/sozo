import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/profile/data/contributors_service.dart';
import 'package:soplay/features/profile/domain/entities/contributor.dart';
import 'package:soplay/features/profile/presentation/widgets/settings_tiles.dart';

/// Everyone who has committed to Sozo, and a way in for the next one.
class ContributorsSection extends StatefulWidget {
  const ContributorsSection({super.key});

  static const String contributingUrl =
      '${AppConstants.sozoRepoUrl}/blob/master/CONTRIBUTING.md';

  @override
  State<ContributorsSection> createState() => _ContributorsSectionState();
}

class _ContributorsSectionState extends State<ContributorsSection> {
  final ContributorsService _service = getIt<ContributorsService>();

  @override
  void initState() {
    super.initState();
    _service.refresh();
  }

  static Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Contributor>?>(
      valueListenable: _service.list,
      builder: (context, people, _) {
        final title = 'profile.contributors'.tr();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsLabel(
              people == null ? title : '$title · ${people.length}',
            ),
            SettingsCard(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                  child: people != null
                      ? _Grid(people: people, onOpen: _open)
                      : ValueListenableBuilder<bool>(
                          valueListenable: _service.failed,
                          builder: (_, failed, _) => failed
                              ? _QuietError(onRetry: _service.refresh)
                              : const _Skeleton(),
                        ),
                ),
                const SettingsDivider(),
                SettingsNavTile(
                  icon: Icons.volunteer_activism_outlined,
                  title: 'profile.become_contributor'.tr(),
                  subtitle: 'profile.become_contributor_body'.tr(),
                  onTap: () => _open(ContributorsSection.contributingUrl),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

const double _avatar = 44;
const double _cell = 64;

class _Grid extends StatelessWidget {
  const _Grid({required this.people, required this.onOpen});

  final List<Contributor> people;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final px = (_avatar * MediaQuery.devicePixelRatioOf(context)).round();
    return Wrap(
      spacing: 6,
      runSpacing: 12,
      children: [
        for (final c in people)
          HoverTap(
            borderRadius: 12,
            onTap: () => onOpen(c.htmlUrl),
            child: Semantics(
              label: c.login,
              excludeSemantics: true,
              child: SizedBox(
                width: _cell,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipOval(
                      child: c.avatarUrl.isEmpty
                          ? const _AvatarFallback()
                          : CachedNetworkImage(
                              imageUrl: Contributor.sizedAvatar(
                                c.avatarUrl,
                                px,
                              ),
                              width: _avatar,
                              height: _avatar,
                              memCacheWidth: px,
                              fit: BoxFit.cover,
                              placeholder: (_, _) => const _AvatarFallback(),
                              errorWidget: (_, _, _) => const _AvatarFallback(),
                            ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      c.login,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _avatar,
      height: _avatar,
      color: AppColors.surfaceVariant,
      child: const Icon(
        Icons.person_rounded,
        color: AppColors.textHint,
        size: 22,
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 12,
      children: [
        for (var i = 0; i < 6; i++)
          SizedBox(
            width: _cell,
            child: Column(
              children: [
                Container(
                  width: _avatar,
                  height: _avatar,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(height: 7),
                Container(
                  width: 40,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _QuietError extends StatelessWidget {
  const _QuietError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.cloud_off_rounded, color: AppColors.textHint, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'profile.contributors_error'.tr(),
            style: const TextStyle(color: AppColors.textHint, fontSize: 12),
          ),
        ),
        TextButton(onPressed: onRetry, child: Text('general.retry'.tr())),
      ],
    );
  }
}
