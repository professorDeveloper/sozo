import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/player/media_controller.dart'
    show warmUpPlayerEngine;
import 'package:soplay/core/player/player_engine.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/subtitles/subtitle_languages.dart';
import 'package:soplay/features/detail/domain/entities/subtitle_style.dart';
import 'package:soplay/features/detail/presentation/widgets/player_engine_sheet.dart';
import 'package:soplay/features/profile/presentation/widgets/settings_tiles.dart';

/// Settings → Player. Every control here seeds a knob that already exists
/// inside the fullscreen player.
///
/// Two rules kept this screen honest and should keep it that way:
///
/// 1. Nothing is listed that the player does not already read. A toggle whose
///    value nobody consults is worse than a missing feature, because it looks
///    like it worked.
/// 2. These are *defaults*, not locks. Changing speed or fill mode mid-video
///    still works and still does not write back here, so a one-off tweak never
///    silently becomes permanent.
///
/// The subtitle block is the exception to (1) in a useful direction: those
/// values were always persisted, but the only way to reach them was the
/// appearance sheet inside the player, which is itself gated on the current
/// source actually having subtitles. A user whose provider serves none could
/// never open it. Same Hive key, same [SubtitleStyle] object — this is just a
/// second door onto it.
class PlayerSettingsPage extends StatefulWidget {
  const PlayerSettingsPage({super.key});

  @override
  State<PlayerSettingsPage> createState() => _PlayerSettingsPageState();
}

class _PlayerSettingsPageState extends State<PlayerSettingsPage> {
  final HiveService _hive = getIt<HiveService>();

  late PlayerEngine _engine;
  late bool _askOnPlay;
  late double _speed;
  late String _fit;
  late bool _autoNext;
  late int _seekSeconds;
  late double _boost;
  late bool _brightnessGesture;
  late bool _volumeGesture;
  late bool _keepScreenOn;
  late SubtitleStyle _subtitle;
  late bool _autoTranslate;
  late String _translateLang;

  static const List<double> _speedChoices = [
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    1.75,
    2.0,
  ];
  static const List<int> _seekChoices = [5, 10, 30];
  static const List<double> _boostChoices = [1.5, 2.0, 2.5, 3.0];
  static const List<String> _fitChoices = ['contain', 'cover', 'fill'];

  /// Startup timing, debug builds only. Kept until the "settings opens slowly"
  /// report is settled — it prints the split between reading Hive and painting
  /// the first frame, which is the only way to tell a slow read from a slow
  /// layout.
  final Stopwatch _openWatch = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    _engine = PlayerEngine.fromId(_hive.getPlayerEngine());
    _askOnPlay = _hive.askEngineOnPlay;
    _speed = _hive.getDefaultPlaybackSpeed();
    _fit = _hive.getDefaultPlayerFit();
    _autoNext = _hive.autoPlayNextEpisode;
    _seekSeconds = _hive.getDoubleTapSeekSeconds();
    _boost = _hive.getLongPressBoost();
    _brightnessGesture = _hive.brightnessGestureEnabled;
    _volumeGesture = _hive.volumeGestureEnabled;
    _keepScreenOn = _hive.keepScreenOn;
    _subtitle = _hive.getSubtitleStyle();
    _autoTranslate = _hive.getSubtitleAutoTranslate();
    _translateLang = _hive.getSubtitleTranslateLang();
    if (kDebugMode) {
      final readMs = _openWatch.elapsedMilliseconds;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        debugPrint(
          '[PLAYER-SETTINGS] hive read ${readMs}ms, '
          'first frame ${_openWatch.elapsedMilliseconds}ms',
        );
      });
    }
  }

  /// Stored speeds may not be one of [_speedChoices] — the in-player sheet can
  /// leave 1.75 behind, and an older build wrote values this list never had.
  /// Snapping keeps the dropdown from rendering a selection that is not in its
  /// own menu.
  double get _speedValue => _speedChoices.contains(_speed) ? _speed : 1.0;
  int get _seekValue => _seekChoices.contains(_seekSeconds) ? _seekSeconds : 10;
  double get _boostValue => _boostChoices.contains(_boost) ? _boost : 2.0;
  String get _fitValue => _fitChoices.contains(_fit) ? _fit : 'contain';

  void _saveSubtitle(SubtitleStyle next) {
    setState(() => _subtitle = next);
    _hive.saveSubtitleStyle(next);
  }

  /// Must stay in step with `_fitLabel` in player_page.controls.dart — the
  /// same three modes are named there and the two lists disagreeing would be
  /// worse than either naming alone.
  String _fitLabel(String id) => switch (id) {
    'cover' => 'player.fit_fill'.tr(),
    'fill' => 'player.fit_stretch'.tr(),
    _ => 'player.fit_original'.tr(),
  };

  String _speedLabel(double v) =>
      '${v.toString().replaceFirst(RegExp(r'\.0$'), '')}×';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'profile.section_player'.tr(),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          if (canChoosePlayerEngine) ...[
            SettingsLabel('profile.player_engine_section'.tr()),
            SettingsCard(
              children: [
                for (var i = 0; i < PlayerEngine.values.length; i++) ...[
                  if (i > 0) const SettingsDivider(),
                  _EngineRow(
                    engine: PlayerEngine.values[i],
                    selected: PlayerEngine.values[i] == _engine,
                    onTap: () {
                      final picked = PlayerEngine.values[i];
                      setState(() => _engine = picked);
                      _hive.savePlayerEngine(picked.id);
                      // Load libmpv now rather than on the next tap of play:
                      // the cost is the same, but here nothing is waiting on
                      // it. No-op for the other two engines.
                      unawaited(warmUpPlayerEngine());
                    },
                  ),
                ],
              ],
            ),
            if (_engine == PlayerEngine.external)
              SettingsFootnote('profile.player_engine_external_note'.tr()),
            const SizedBox(height: 10),
            SettingsCard(
              children: [
                SettingsSwitchTile(
                  icon: Icons.quiz_outlined,
                  title: 'profile.ask_engine_on_play'.tr(),
                  subtitle: 'profile.ask_engine_on_play_desc'.tr(),
                  value: _askOnPlay,
                  onChanged: (v) {
                    setState(() => _askOnPlay = v);
                    _hive.setAskEngineOnPlay(v);
                  },
                ),
              ],
            ),
            const SizedBox(height: 22),
          ],

          SettingsLabel('profile.playback_section'.tr()),
          SettingsCard(
            children: [
              SettingsDropdownTile<double>(
                icon: Icons.speed_rounded,
                title: 'profile.default_speed'.tr(),
                subtitle: 'profile.default_speed_desc'.tr(),
                value: _speedValue,
                options: _speedChoices,
                labelOf: _speedLabel,
                onChanged: (v) {
                  setState(() => _speed = v);
                  _hive.saveDefaultPlaybackSpeed(v);
                },
              ),
              const SettingsDivider(),
              SettingsDropdownTile<String>(
                icon: Icons.aspect_ratio_rounded,
                title: 'profile.default_fit'.tr(),
                subtitle: 'profile.default_fit_desc'.tr(),
                value: _fitValue,
                options: _fitChoices,
                labelOf: _fitLabel,
                onChanged: (v) {
                  setState(() => _fit = v);
                  _hive.saveDefaultPlayerFit(v);
                },
              ),
              const SettingsDivider(),
              SettingsSwitchTile(
                icon: Icons.playlist_play_rounded,
                title: 'profile.auto_next_episode'.tr(),
                subtitle: 'profile.auto_next_episode_desc'.tr(),
                value: _autoNext,
                onChanged: (v) {
                  setState(() => _autoNext = v);
                  _hive.setAutoPlayNextEpisode(v);
                },
              ),
              const SettingsDivider(),
              SettingsSwitchTile(
                icon: Icons.lightbulb_outline_rounded,
                title: 'profile.keep_screen_on'.tr(),
                subtitle: 'profile.keep_screen_on_desc'.tr(),
                value: _keepScreenOn,
                onChanged: (v) {
                  setState(() => _keepScreenOn = v);
                  _hive.setKeepScreenOn(v);
                },
              ),
            ],
          ),

          const SizedBox(height: 22),
          SettingsLabel('profile.gestures_section'.tr()),
          SettingsCard(
            children: [
              SettingsDropdownTile<int>(
                icon: Icons.fast_forward_rounded,
                title: 'profile.seek_step'.tr(),
                subtitle: 'profile.seek_step_desc'.tr(),
                value: _seekValue,
                options: _seekChoices,
                labelOf: (v) =>
                    'profile.seconds_short'.tr(args: <String>[v.toString()]),
                onChanged: (v) {
                  setState(() => _seekSeconds = v);
                  _hive.saveDoubleTapSeekSeconds(v);
                },
              ),
              const SettingsDivider(),
              SettingsDropdownTile<double>(
                icon: Icons.touch_app_rounded,
                title: 'profile.long_press_boost'.tr(),
                subtitle: 'profile.long_press_boost_desc'.tr(),
                value: _boostValue,
                options: _boostChoices,
                labelOf: _speedLabel,
                onChanged: (v) {
                  setState(() => _boost = v);
                  _hive.saveLongPressBoost(v);
                },
              ),
              const SettingsDivider(),
              SettingsSwitchTile(
                icon: Icons.brightness_6_rounded,
                title: 'profile.brightness_gesture'.tr(),
                subtitle: 'profile.brightness_gesture_desc'.tr(),
                value: _brightnessGesture,
                onChanged: (v) {
                  setState(() => _brightnessGesture = v);
                  _hive.setBrightnessGestureEnabled(v);
                },
              ),
              const SettingsDivider(),
              SettingsSwitchTile(
                icon: Icons.volume_up_rounded,
                title: 'profile.volume_gesture'.tr(),
                subtitle: 'profile.volume_gesture_desc'.tr(),
                value: _volumeGesture,
                onChanged: (v) {
                  setState(() => _volumeGesture = v);
                  _hive.setVolumeGestureEnabled(v);
                },
              ),
            ],
          ),

          const SizedBox(height: 22),
          SettingsLabel('player.subtitle_translation'.tr()),
          SettingsCard(
            children: [
              SettingsSwitchTile(
                icon: Icons.translate_rounded,
                title: 'player.auto_translate'.tr(),
                subtitle: 'player.auto_translate_desc'.tr(),
                value: _autoTranslate,
                onChanged: (v) {
                  setState(() => _autoTranslate = v);
                  _hive.setSubtitleAutoTranslate(v);
                },
              ),
              SettingsDivider(),
              SettingsDropdownTile<String>(
                icon: Icons.language_rounded,
                title: 'player.translate_to'.tr(),
                value: kSubtitleTranslateLanguages
                        .any((l) => l.$1 == _translateLang)
                    ? _translateLang
                    : 'uz',
                options: [for (final l in kSubtitleTranslateLanguages) l.$1],
                labelOf: (v) => kSubtitleTranslateLanguages
                    .firstWhere((l) => l.$1 == v,
                        orElse: () => kSubtitleTranslateLanguages.first)
                    .$2,
                onChanged: (v) {
                  setState(() => _translateLang = v);
                  _hive.setSubtitleTranslateLang(v);
                },
              ),
            ],
          ),
          SettingsFootnote('player.translate_note'.tr()),

          const SizedBox(height: 22),
          SettingsLabel('player.subtitle_style'.tr()),
          _SubtitlePreview(style: _subtitle),
          const SizedBox(height: 10),
          SettingsCard(
            children: [
              SettingsDropdownTile<double>(
                icon: Icons.format_size_rounded,
                title: 'player.font_size'.tr(),
                value: _subtitle.fontSize,
                options: const [12, 14, 16, 18, 20, 24, 28, 32],
                labelOf: (v) => v.toInt().toString(),
                onChanged: (v) =>
                    _saveSubtitle(_subtitle.copyWith(fontSize: v)),
              ),
              const SettingsDivider(),
              SettingsDropdownTile<SubtitleEdge>(
                icon: Icons.border_style_rounded,
                title: 'player.edge'.tr(),
                value: _subtitle.edge,
                options: SubtitleEdge.values,
                labelOf: (v) => switch (v) {
                  SubtitleEdge.none => 'player.none'.tr(),
                  SubtitleEdge.shadow => 'player.shadow'.tr(),
                  SubtitleEdge.outline => 'player.outline'.tr(),
                },
                onChanged: (v) => _saveSubtitle(_subtitle.copyWith(edge: v)),
              ),
              const SettingsDivider(),
              SettingsDropdownTile<SubtitlePosition>(
                icon: Icons.vertical_align_bottom_rounded,
                title: 'player.position'.tr(),
                value: _subtitle.position,
                options: SubtitlePosition.values,
                labelOf: (v) => switch (v) {
                  SubtitlePosition.lower => 'player.lower'.tr(),
                  SubtitlePosition.normal => 'player.default'.tr(),
                  SubtitlePosition.higher => 'player.higher'.tr(),
                },
                onChanged: (v) =>
                    _saveSubtitle(_subtitle.copyWith(position: v)),
              ),
              const SettingsDivider(),
              SettingsSwitchTile(
                icon: Icons.format_bold_rounded,
                title: 'player.bold'.tr(),
                value: _subtitle.bold,
                onChanged: (v) => _saveSubtitle(_subtitle.copyWith(bold: v)),
              ),
              const SettingsDivider(),
              _SubtitleColorRow(
                selected: _subtitle.textColor,
                onPick: (c) => _saveSubtitle(_subtitle.copyWith(textColor: c)),
              ),
              const SettingsDivider(),
              _SubtitleOpacityRow(
                value: _subtitle.bgOpacity,
                onChanged: (v) =>
                    _saveSubtitle(_subtitle.copyWith(bgOpacity: v)),
              ),
            ],
          ),
          SettingsFootnote('profile.subtitle_style_note'.tr()),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: () => _saveSubtitle(SubtitleStyle.defaults()),
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: Text('player.reset'.tr()),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live sample of the current subtitle settings, over a stand-in for video.
/// Without it every control on the block is guesswork — "shadow vs outline at
/// size 18" means nothing until you see it.
class _SubtitlePreview extends StatelessWidget {
  const _SubtitlePreview({required this.style});

  final SubtitleStyle style;

  @override
  Widget build(BuildContext context) {
    final color = Color(style.textColor);
    return Container(
      height: 92,
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF23252B), Color(0xFF121316)],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: style.bgOpacity),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'player.subtitle_preview_text'.tr(),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: style.fontSize,
            fontWeight: style.bold ? FontWeight.w700 : FontWeight.w400,
            shadows: switch (style.edge) {
              SubtitleEdge.none => const <Shadow>[],
              SubtitleEdge.shadow => const <Shadow>[
                Shadow(
                  color: Colors.black,
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
              SubtitleEdge.outline => const <Shadow>[
                Shadow(
                  color: Colors.black,
                  blurRadius: 2,
                  offset: Offset(-1, -1),
                ),
                Shadow(
                  color: Colors.black,
                  blurRadius: 2,
                  offset: Offset(1, -1),
                ),
                Shadow(
                  color: Colors.black,
                  blurRadius: 2,
                  offset: Offset(1, 1),
                ),
                Shadow(
                  color: Colors.black,
                  blurRadius: 2,
                  offset: Offset(-1, 1),
                ),
              ],
            },
          ),
        ),
      ),
    );
  }
}

class _SubtitleColorRow extends StatelessWidget {
  const _SubtitleColorRow({required this.selected, required this.onPick});

  /// Mirrors `_subtitleColorPresets` in player_page.models.dart. Kept as a
  /// literal rather than imported because that list is library-private to the
  /// player; if one changes, change both.
  static const List<int> _presets = <int>[
    0xFFFFFFFF,
    0xFFFFEB3B,
    0xFF00E5FF,
    0xFF76FF03,
    0xFFFF80AB,
    0xFFFF5252,
  ];

  final int selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.palette_outlined,
              color: AppColors.textSecondary,
              size: 18,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'player.text_color'.tr(),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          for (final c in _presets)
            GestureDetector(
              onTap: () => onPick(c),
              child: Container(
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(left: 7),
                decoration: BoxDecoration(
                  color: Color(c),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: c == selected ? AppColors.primary : Colors.white24,
                    width: c == selected ? 2.5 : 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SubtitleOpacityRow extends StatelessWidget {
  const _SubtitleOpacityRow({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.opacity_rounded,
              color: AppColors.textSecondary,
              size: 18,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 3,
            child: Text(
              'player.background'.tr(),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Slider(
              value: value.clamp(0.0, 1.0),
              activeColor: AppColors.primary,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              '${(value * 100).round()}%',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Engine picker row. Same layout as the one in the play-time sheet so the
/// two screens agree about what each backend looks like.
class _EngineRow extends StatelessWidget {
  const _EngineRow({
    required this.engine,
    required this.selected,
    required this.onTap,
  });

  final PlayerEngine engine;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : AppColors.textSecondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  playerEngineIcon(engine),
                  size: 18,
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            playerEngineTitleKey(engine).tr(),
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (engine == PlayerEngine.native) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'profile.player_engine_badge_default'.tr(),
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      playerEngineDescKey(engine).tr(),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
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
                size: 20,
                color: selected ? AppColors.primary : AppColors.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
