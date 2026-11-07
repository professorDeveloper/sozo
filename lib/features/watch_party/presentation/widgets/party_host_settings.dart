import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/watch_party/data/watch_party_service.dart';
import 'package:soplay/features/watch_party/domain/entities/party_room.dart';

/// The host's room controls in the lobby: size, who drives playback, the lock
/// and "wait for everyone". Each change goes out as `party:settings` and comes
/// back to every member, this one included, so the room is the only state.
class PartyHostSettings extends StatelessWidget {
  const PartyHostSettings({
    super.key,
    required this.room,
    required this.service,
  });

  final PartyRoom room;
  final WatchPartyService service;

  static const int minMembers = 2;

  @override
  Widget build(BuildContext context) {
    final limit = room.maxMembersLimit < minMembers
        ? minMembers
        : room.maxMembersLimit;
    final size = room.maxMembers.clamp(minMembers, limit);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 6, 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'watch_party.settings_title'.tr(),
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  'watch_party.room_size'.tr(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'watch_party.room_size_less'.tr(),
                icon: const Icon(Icons.remove_rounded),
                onPressed: size > minMembers
                    ? () => service.updateSettings(maxMembers: size - 1)
                    : null,
              ),
              SizedBox(
                width: 28,
                child: Text(
                  '$size',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'watch_party.room_size_more'.tr(),
                icon: const Icon(Icons.add_rounded),
                onPressed: size < limit
                    ? () => service.updateSettings(maxMembers: size + 1)
                    : null,
              ),
            ],
          ),
          _Toggle(
            title: 'watch_party.only_host_setting'.tr(),
            value: room.onlyHostControls,
            onChanged: (v) => service.updateSettings(onlyHostControls: v),
          ),
          _Toggle(
            title: 'watch_party.lock_room'.tr(),
            subtitle: 'watch_party.lock_room_hint'.tr(),
            value: room.locked,
            onChanged: (v) => service.updateSettings(locked: v),
          ),
          _Toggle(
            title: 'watch_party.wait_for_all'.tr(),
            subtitle: 'watch_party.wait_for_all_hint'.tr(),
            value: room.waitForAll,
            onChanged: (v) => service.updateSettings(waitForAll: v),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      dense: true,
      contentPadding: const EdgeInsetsDirectional.only(end: 4),
      value: value,
      onChanged: onChanged,
      // Same as the settings switches: a white thumb on an accent track.
      activeThumbColor: Colors.white,
      activeTrackColor: AppColors.primary,
      title: Text(
        title,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(color: AppColors.textHint, fontSize: 12),
            ),
    );
  }
}
