import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/player/media_controller.dart'
    show warmUpPlayerEngine;
import 'package:soplay/core/player/player_engine.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';

/// Icon shown for each backend. Shared with Settings → Player so the row a
/// user taps in the sheet is visually the same row they see in settings.
IconData playerEngineIcon(PlayerEngine engine) => switch (engine) {
      PlayerEngine.native => Icons.play_circle_outline_rounded,
      PlayerEngine.mediaKit => Icons.graphic_eq_rounded,
      PlayerEngine.external => Icons.open_in_new_rounded,
    };

String playerEngineTitleKey(PlayerEngine engine) => switch (engine) {
      PlayerEngine.native => 'profile.player_engine_native',
      PlayerEngine.mediaKit => 'profile.player_engine_media_kit',
      PlayerEngine.external => 'profile.player_engine_external',
    };

String playerEngineDescKey(PlayerEngine engine) => switch (engine) {
      PlayerEngine.native => 'profile.player_engine_native_desc',
      PlayerEngine.mediaKit => 'profile.player_engine_media_kit_desc',
      PlayerEngine.external => 'profile.player_engine_external_desc',
    };

/// Asks which backend should decode the video that is about to start.
///
/// Shown before the controller is built, so whichever engine is picked is the
/// one that actually runs — there is no mid-playback swap and no wasted
/// initialization of the engine the user did not want.
///
/// The choice is written straight to Hive rather than returned as a one-shot
/// override: `resolvePlayerEngine()` re-reads the box on every controller
/// build, so persisting is what makes the pick take effect everywhere (the
/// external-handoff branch in player_page.media.dart reads it independently).
/// It also means "I picked media_kit" survives into Settings → Player instead
/// of silently disagreeing with what the settings screen displays.
///
/// Returns false when the user dismissed the sheet without choosing, so the
/// caller can back out of playback instead of starting with an engine the user
/// never confirmed.
/// Asks for the engine BEFORE the player is opened, when the setting is on.
///
/// ## Why this is not inside the player
///
/// It used to be, and the sheet then arrived over a player that was already on
/// screen with nothing decoded — a black rectangle with a question on top,
/// which reads as the video having failed rather than as a choice being asked
/// for. Dismissing it then had to close a page the user had just opened.
///
/// Asked here, the question is part of pressing Play: answer it and the player
/// opens on the engine you chose; dismiss it and nothing happened.
///
/// Returns false when the user backed out, and the caller must not navigate.
Future<bool> confirmPlayerEngine(BuildContext context) async {
  if (!canChoosePlayerEngine) return true;
  if (!getIt<HiveService>().askEngineOnPlay) return true;
  return showPlayerEngineSheet(context);
}

Future<bool> showPlayerEngineSheet(BuildContext context) async {
  if (!canChoosePlayerEngine) return true;
  final hive = getIt<HiveService>();
  var selected = PlayerEngine.fromId(hive.getPlayerEngine());
  // Unticked by default — opting out of a prompt should be a deliberate act,
  // not something that happens because the user tapped straight through.
  var dontAskAgain = false;

  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: const Color(0xFF111111),
    isScrollControlled: true,
    // Deliberately dismissible: BACK / tapping outside means "not now", and the
    // caller treats that as a cancelled playback rather than a silent default.
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheetContext) => SafeArea(
      child: StatefulBuilder(
        builder: (builderContext, setSheetState) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
                child: Text(
                  'player.engine_sheet_title'.tr(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                child: Text(
                  'player.engine_sheet_subtitle'.tr(),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ),
              for (final engine in PlayerEngine.values)
                _EngineOption(
                  icon: playerEngineIcon(engine),
                  title: playerEngineTitleKey(engine).tr(),
                  description: playerEngineDescKey(engine).tr(),
                  selected: engine == selected,
                  onTap: () => setSheetState(() => selected = engine),
                ),
              if (selected == PlayerEngine.external)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          color: AppColors.textHint, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'profile.player_engine_external_note'.tr(),
                          style: const TextStyle(
                            color: AppColors.textHint,
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              InkWell(
                onTap: () => setSheetState(() => dontAskAgain = !dontAskAgain),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 18, 8),
                  child: Row(
                    children: [
                      Checkbox(
                        value: dontAskAgain,
                        onChanged: (v) =>
                            setSheetState(() => dontAskAgain = v ?? false),
                        activeColor: AppColors.primary,
                        side: const BorderSide(color: Colors.white38),
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'player.engine_sheet_dont_ask'.tr(),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(kButtonRadius),
                      ),
                    ),
                    onPressed: () => Navigator.of(builderContext).pop(true),
                    child: Text(
                      'player.engine_sheet_play'.tr(),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  if (confirmed != true) return false;
  await hive.savePlayerEngine(selected.id);
  if (dontAskAgain) await hive.setAskEngineOnPlay(false);
  // Awaited, not fire-and-forget: playback starts the moment this returns, and
  // loading libmpv concurrently with the first Player() is the stall this call
  // exists to avoid. No-op unless media_kit was picked.
  await warmUpPlayerEngine();
  return true;
}

class _EngineOption extends StatelessWidget {
  const _EngineOption({
    required this.icon,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      child: Material(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppColors.primary : Colors.transparent,
                width: 1.2,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: selected ? AppColors.primary : Colors.white70,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: selected
                              ? AppColors.primary
                              : AppColors.textPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 19,
                  color: selected ? AppColors.primary : AppColors.textHint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
