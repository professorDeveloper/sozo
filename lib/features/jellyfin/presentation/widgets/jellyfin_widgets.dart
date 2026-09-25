import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/jellyfin/data/jellyfin_api.dart';
import 'package:soplay/features/jellyfin/data/jellyfin_bridge.dart';
import 'package:soplay/features/profile/presentation/widgets/settings_tiles.dart';

/// What to tell someone about a failed request. [login] turns a 401 into
/// "wrong password" rather than "session expired".
String jellyfinErrorText(Object error, {bool login = false}) {
  if (error is JellyfinException) {
    return switch (error.kind) {
      JellyfinErrorKind.unreachable => 'jellyfin.error_unreachable'.tr(),
      JellyfinErrorKind.notJellyfin => 'jellyfin.error_not_jellyfin'.tr(),
      JellyfinErrorKind.unauthorized =>
        (login ? 'jellyfin.error_login' : 'jellyfin.error_session').tr(),
      JellyfinErrorKind.server =>
        '${'jellyfin.error_server'.tr()} (${error.detail})',
    };
  }
  return 'general.error'.tr();
}

class JellyfinLogo extends StatelessWidget {
  const JellyfinLogo({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: CachedNetworkImage(
        imageUrl: JellyfinBridge.icon,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, _) => _fallback(),
        errorWidget: (_, _, _) => _fallback(),
      ),
    );
  }

  Widget _fallback() => Container(
    width: size,
    height: size,
    color: AppColors.surfaceVariant,
    child: Icon(Icons.dns_rounded, size: size * 0.55, color: AppColors.primary),
  );
}

IconData _libraryIcon(String? collectionType) => switch (collectionType) {
  'movies' => Icons.movie_outlined,
  'tvshows' => Icons.tv_rounded,
  'homevideos' => Icons.videocam_outlined,
  _ => Icons.video_library_outlined,
};

/// One switch per playable library.
class JellyfinLibraryToggles extends StatelessWidget {
  const JellyfinLibraryToggles({
    super.key,
    required this.libraries,
    required this.hidden,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> libraries;
  final Set<String> hidden;
  final void Function(String id, bool visible) onChanged;

  @override
  Widget build(BuildContext context) {
    if (libraries.isEmpty) {
      return SettingsCard(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const Icon(
                  Icons.video_library_outlined,
                  color: AppColors.textHint,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'jellyfin.libraries_empty'.tr(),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return SettingsCard(
      children: [
        for (var i = 0; i < libraries.length; i++) ...[
          if (i > 0) const SettingsDivider(),
          SettingsSwitchTile(
            icon: _libraryIcon(libraries[i]['CollectionType']?.toString()),
            title: (libraries[i]['Name'] ?? '').toString(),
            value: !hidden.contains(libraries[i]['Id'].toString()),
            onChanged: (v) => onChanged(libraries[i]['Id'].toString(), v),
          ),
        ],
      ],
    );
  }
}

/// A one-line success note, the positive twin of `AuthErrorBanner`.
class JellyfinOkBanner extends StatelessWidget {
  const JellyfinOkBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          child: Row(
            children: [
              const Icon(
                Icons.check_circle_outline_rounded,
                size: 18,
                color: AppColors.success,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
