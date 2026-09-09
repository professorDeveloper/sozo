import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/features/detail/domain/playback/player_info_fields.dart';

/// Picks which rows the player info overlay shows.
///
/// The overlay used to be one switch: fifteen rows over the picture, or none.
/// Everything is a wall people turn off and never turn back on; nothing makes
/// the whole panel dead weight. This is the middle, and it is where the
/// "Stats for nerds" comparison stops — that panel is for the person who wrote
/// the player, and this one is for the person watching, so it defaults to the
/// five rows that answer an actual complaint rather than to all of them.
///
/// Writes on every tap rather than on dismiss. A sheet with no Save button and
/// no confirmation must not be able to lose a choice to a swipe-down.
class PlayerInfoFieldsSheet extends StatefulWidget {
  const PlayerInfoFieldsSheet({super.key, this.onChanged});

  /// Lets an open player re-render its overlay while the sheet is still up, so
  /// the effect of each tap is visible behind it.
  final ValueChanged<Set<String>>? onChanged;

  static Future<Set<String>?> show(
    BuildContext context, {
    ValueChanged<Set<String>>? onChanged,
  }) =>
      showAdaptiveModal<Set<String>>(
        context: context,
        backgroundColor: const Color(0xFF111111),
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) => PlayerInfoFieldsSheet(onChanged: onChanged),
      );

  @override
  State<PlayerInfoFieldsSheet> createState() => _PlayerInfoFieldsSheetState();
}

class _PlayerInfoFieldsSheetState extends State<PlayerInfoFieldsSheet> {
  final HiveService _hive = getIt<HiveService>();
  late Set<String> _enabled =
      PlayerInfoFields.fromStored(_hive.getPlayerInfoFields());

  void _apply(Set<String> next) {
    setState(() => _enabled = next);
    _hive.setPlayerInfoFields(PlayerInfoFields.toStored(next));
    widget.onChanged?.call(next);
  }

  void _toggle(String id, bool on) {
    final next = Set<String>.of(_enabled);
    if (on) {
      next.add(id);
    } else {
      next.remove(id);
    }
    _apply(next);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return SafeArea(
      child: ConstrainedBox(
        // Half the screen at most: the sheet is opened from the player, and one
        // that covers the video hides the thing the rows are describing.
        constraints: BoxConstraints(maxHeight: media.size.height * 0.72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'player.info_title'.tr(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'player.info_fields_desc'.tr(),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Only offered when it would do something — a Reset that is
                  // always there but usually inert is a control people learn to
                  // ignore.
                  if (!PlayerInfoFields.isDefault(_enabled))
                    TextButton(
                      onPressed: () => _apply(PlayerInfoFields.defaults),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primaryLight,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 34),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'general.reset'.tr(),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: PlayerInfoFields.all.length,
                itemBuilder: (_, i) {
                  final f = PlayerInfoFields.all[i];
                  final on = _enabled.contains(f.id);
                  return InkWell(
                    onTap: () => _toggle(f.id, !on),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 2, 12, 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              f.labelKey.tr(),
                              style: TextStyle(
                                color: on ? Colors.white : Colors.white70,
                                fontSize: 14,
                                fontWeight:
                                    on ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                          ),
                          Checkbox(
                            value: on,
                            onChanged: (v) => _toggle(f.id, v ?? false),
                            activeColor: AppColors.primary,
                            checkColor: AppColors.onPrimary,
                            side: const BorderSide(
                              color: Colors.white38,
                              width: 1.6,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}
