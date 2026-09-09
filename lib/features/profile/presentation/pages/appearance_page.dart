import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_accent.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_palette.dart';
import 'package:soplay/core/theme/theme_controller.dart';
import 'package:soplay/features/profile/presentation/widgets/library_accents.dart';
import 'package:soplay/features/profile/presentation/widgets/settings_tiles.dart';
import 'package:soplay/features/profile/presentation/widgets/theme_preview.dart';

/// Settings → Appearance.
///
/// Two settings, both of which repaint the entire app the instant they are
/// touched: the accent colour and whether the neutrals go to true black.
///
/// Everything on this page is deliberately shown rather than described. The
/// accent is a row of colours *and* a full miniature of the app; the darkness
/// choice is two miniatures side by side. Nothing here asks the user to imagine
/// what "AMOLED" will do to a screen they are not currently looking at.
class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'appearance.title'.tr(),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: const [_ResetAction()],
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.only(top: 4, bottom: 40),
        child: AppearanceSettings(),
      ),
    );
  }
}

/// The body of [AppearancePage], on its own so the desktop Profile can drop it
/// straight into its "Appearance" panel instead of keeping a second copy.
class AppearanceSettings extends StatefulWidget {
  const AppearanceSettings({super.key, this.showResetRow = false});

  /// Desktop has no app bar to hang the reset action off, so it gets a row.
  final bool showResetRow;

  @override
  State<AppearanceSettings> createState() => _AppearanceSettingsState();
}

class _AppearanceSettingsState extends State<AppearanceSettings> {
  final ThemeController _theme = getIt<ThemeController>();

  /// Held in the State, not started in build(): this page rebuilds on every
  /// colour tap, and a future created in build() would re-decode five posters
  /// each time.
  final Future<List<AppAccent>> _libraryAccents = LibraryAccents.load();

  // No addListener / setState pair here on purpose: a theme change already
  // marks the whole element tree dirty from MyApp, so this page rebuilds with
  // everything else. Listening as well would just rebuild it twice.

  Future<void> _pick(AppAccent accent) async {
    _tap();
    await _theme.setAccent(accent);
  }

  Future<void> _setAmoled(bool value) async {
    _tap();
    await _theme.setAmoled(value);
  }

  void _tap() {
    if (isMobilePlatform) HapticFeedback.selectionClick();
  }

  Future<void> _setNavTinted(bool value) async {
    _tap();
    await _theme.setNavTinted(value);
  }

  Future<void> _shuffle() async {
    _tap();
    await _theme.cycleAccent();
  }

  Future<void> _openCustom() async {
    _tap();
    final picked = await showCustomAccentSheet(
      context,
      initial: _theme.customSeed ?? _theme.accent.base,
    );
    if (picked != null) await _theme.setCustomAccent(picked);
  }

  @override
  Widget build(BuildContext context) {
    final accent = _theme.accent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Live preview ────────────────────────────────────────────────
          SettingsLabel('appearance.section_preview'.tr()),
          const _PreviewStage(),
          const SizedBox(height: 20),

          // ── Accent ──────────────────────────────────────────────────────
          SettingsLabel('appearance.section_accent'.tr()),
          SettingsCard(
            children: [
              _AccentGrid(selected: accent, onPick: _pick),
              const SettingsDivider(),
              _CurrentAccentRow(accent: accent),
              const SettingsDivider(),
              _CustomAccentRow(active: accent.isCustom, onTap: _openCustom),
            ],
          ),
          SettingsFootnote('appearance.accent_footnote'.tr()),
          const SizedBox(height: 20),

          // ── From the user's own library ─────────────────────────────────
          _LibraryAccentSection(
            accents: _libraryAccents,
            selected: accent,
            onPick: (a) async {
              _tap();
              await _theme.setCustomAccent(a.base);
            },
          ),

          // ── Darkness ────────────────────────────────────────────────────
          SettingsLabel('appearance.section_darkness'.tr()),
          SettingsCard(
            children: [
              _DarknessPicker(
                accent: accent,
                value: _theme.darkness,
                onChanged: (d) => _setAmoled(d == AppDarkness.black),
              ),
              const SettingsDivider(),
              SettingsSwitchTile(
                icon: Icons.contrast_rounded,
                title: 'appearance.darkness_black'.tr(),
                subtitle: 'appearance.darkness_black_desc'.tr(),
                value: _theme.isAmoled,
                onChanged: _setAmoled,
              ),
            ],
          ),
          SettingsFootnote('appearance.amoled_footnote'.tr()),
          const SizedBox(height: 20),

          // ── Where the accent is allowed to go ───────────────────────────
          SettingsLabel('appearance.section_extras'.tr()),
          SettingsCard(
            children: [
              SettingsSwitchTile(
                icon: Icons.dashboard_customize_rounded,
                title: 'appearance.tint_nav'.tr(),
                subtitle: 'appearance.tint_nav_desc'.tr(),
                value: _theme.isNavTinted,
                onChanged: _setNavTinted,
              ),
              const SettingsDivider(),
              _ActionRow(
                icon: Icons.shuffle_rounded,
                title: 'appearance.shuffle'.tr(),
                subtitle: 'appearance.shuffle_desc'.tr(),
                onTap: _shuffle,
              ),
            ],
          ),

          if (widget.showResetRow) ...[
            const SizedBox(height: 20),
            SettingsCard(
              children: [
                _ResetRow(
                  enabled: !_theme.isDefault,
                  onReset: () async {
                    _tap();
                    await _theme.reset();
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Preview ─────────────────────────────────────────────────────────────────

/// Wraps the component sample.
///
/// No device frame and no stage lighting: the sample is a real card on a real
/// background, and dressing it up as a photographed object would put back the
/// suggestion that it is a picture of a screen somewhere.
class _PreviewStage extends StatelessWidget {
  const _PreviewStage();

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: const ThemePreview(),
    );
  }
}

// ── Accent ──────────────────────────────────────────────────────────────────

class _AccentGrid extends StatelessWidget {
  const _AccentGrid({required this.selected, required this.onPick});

  final AppAccent selected;
  final ValueChanged<AppAccent> onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Only the presets live here, and there are twelve of them — which
          // divides evenly by 6, 4 and 3. So whatever width the card gets, the
          // grid comes out as full rows instead of leaving one swatch stranded
          // on a line of its own. (Custom is a labelled row underneath, where
          // it can say what it is.)
          const gap = 10.0;
          final columns = switch (constraints.maxWidth) {
            >= 420 => 6,
            >= 300 => 6,
            >= 220 => 4,
            _ => 3,
          };
          final size = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final accent in AppAccent.presets)
                _Swatch(
                  size: size,
                  color: accent.base,
                  selected: !selected.isCustom && selected.id == accent.id,
                  onTap: () => onPick(accent),
                  semanticLabel: accent.labelKey.tr(),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The way into the colour wheel. A row rather than a thirteenth circle: it can
/// carry a label, it never breaks the grid's rhythm, and when a custom colour
/// is in force it shows which one.
class _CustomAccentRow extends StatelessWidget {
  const _CustomAccentRow({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  /// Hues around the wheel chip. Twelve is enough for the sweep to read as
  /// continuous at this size.
  static const List<Color> _wheel = [
    Color(0xFFE53935), Color(0xFFF4511E), Color(0xFFFFB300),
    Color(0xFFC0CA33), Color(0xFF43A047), Color(0xFF00897B),
    Color(0xFF039BE5), Color(0xFF3949AB), Color(0xFF8E24AA),
    Color(0xFFD81B60), Color(0xFFE53935),
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const SweepGradient(colors: _wheel),
                  border: Border.all(
                    color: active
                        ? AppColors.textPrimary
                        : AppColors.textPrimary.withValues(alpha: 0.12),
                    width: active ? 2 : 1,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'appearance.custom_title'.tr(),
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (active)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textHint,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.size,
    required this.color,
    required this.selected,
    required this.onTap,
    required this.semanticLabel,
  });

  final double size;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      selected: selected,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // The selection ring sits outside the colour, not on it, so a dark
            // accent and a bright one are equally obviously selected.
            border: Border.all(
              color: selected
                  ? AppColors.textPrimary
                  : AppColors.textPrimary.withValues(alpha: 0.10),
              width: selected ? 2 : 1,
            ),
          ),
          padding: EdgeInsets.all(selected ? 4 : 3),
          child: DecoratedBox(
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            child: selected
                ? Center(
                    child: Icon(
                      Icons.check_rounded,
                      size: size * 0.42,
                      color: Colors.white,
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

/// Names the accent in force and, for a custom one, offers the way back into
/// the picker. Without it the grid is twelve unlabelled dots.
class _CurrentAccentRow extends StatelessWidget {
  const _CurrentAccentRow({required this.accent});

  final AppAccent accent;

  @override
  Widget build(BuildContext context) {
    final hex = accent.base
        .toARGB32()
        .toRadixString(16)
        .padLeft(8, '0')
        .substring(2)
        .toUpperCase();
    return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: accent.base,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.textPrimary.withValues(alpha: 0.12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  accent.labelKey.tr(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                '#$hex',
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 12.5,
                  fontFeatures: [FontFeature.tabularFigures()],
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        );
  }
}

/// The accents the user's own library is made of.
///
/// Hides itself entirely when there is nothing to show — a fresh install, an
/// offline session, posters that failed to decode. An empty labelled card that
/// says "we found nothing" is worse than no card: it turns a bonus into a
/// broken feature.
class _LibraryAccentSection extends StatelessWidget {
  const _LibraryAccentSection({
    required this.accents,
    required this.selected,
    required this.onPick,
  });

  final Future<List<AppAccent>> accents;
  final AppAccent selected;
  final ValueChanged<AppAccent> onPick;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AppAccent>>(
      future: accents,
      builder: (context, snapshot) {
        final found = snapshot.data ?? const <AppAccent>[];
        // AnimatedSize so the row slides in when the posters finish decoding
        // rather than making the page jump under the user's thumb.
        return AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: found.isEmpty
              ? const SizedBox(width: double.infinity)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SettingsLabel('appearance.section_library'.tr()),
                    SettingsCard(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              // Laid out on the same six-column grid as the
                              // preset row above, so the two rows of circles
                              // line up instead of being two different sizes.
                              // Between one and six swatches can turn up, and a
                              // Wrap would stretch two of them into saucers.
                              const gap = 10.0;
                              const columns = 6;
                              final size =
                                  (constraints.maxWidth - gap * (columns - 1)) /
                                      columns;
                              return Wrap(
                                spacing: gap,
                                runSpacing: gap,
                                children: [
                                  for (final accent in found)
                                    _Swatch(
                                      size: size,
                                      color: accent.base,
                                      selected: selected.isCustom &&
                                          selected.base == accent.base,
                                      onTap: () => onPick(accent),
                                      semanticLabel:
                                          'appearance.accent_custom'.tr(),
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    SettingsFootnote('appearance.library_footnote'.tr()),
                    const SizedBox(height: 20),
                  ],
                ),
        );
      },
    );
  }
}

/// A settings row that just does something, with no value to show.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 11.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Darkness ────────────────────────────────────────────────────────────────

class _DarknessPicker extends StatelessWidget {
  const _DarknessPicker({
    required this.accent,
    required this.value,
    required this.onChanged,
  });

  final AppAccent accent;
  final AppDarkness value;
  final ValueChanged<AppDarkness> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _DarknessTile(
              accent: accent,
              darkness: AppDarkness.dark,
              labelKey: 'appearance.darkness_dark',
              descKey: 'appearance.darkness_dark_desc',
              selected: value == AppDarkness.dark,
              onTap: () => onChanged(AppDarkness.dark),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _DarknessTile(
              accent: accent,
              darkness: AppDarkness.black,
              labelKey: 'appearance.darkness_black',
              descKey: 'appearance.darkness_black_desc',
              selected: value == AppDarkness.black,
              onTap: () => onChanged(AppDarkness.black),
            ),
          ),
        ],
      ),
    );
  }
}

class _DarknessTile extends StatelessWidget {
  const _DarknessTile({
    required this.accent,
    required this.darkness,
    required this.labelKey,
    required this.descKey,
    required this.selected,
    required this.onTap,
  });

  final AppAccent accent;
  final AppDarkness darkness;
  final String labelKey;
  final String descKey;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Each tile previews ITS OWN mode in the CURRENT accent — the whole point
    // is to show the user the option they have not chosen.
    final palette = AppPalette.resolve(accent: accent, darkness: darkness);
    return Semantics(
      label: labelKey.tr(),
      selected: selected,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.fromLTRB(9, 9, 9, 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.55)
                  : AppColors.textPrimary.withValues(alpha: 0.07),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DarknessSample(palette: palette),
              const SizedBox(height: 9),
              Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 15,
                    color: selected ? AppColors.primary : AppColors.textHint,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      labelKey.tr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                descKey.tr(),
                maxLines: 2,
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Reset ───────────────────────────────────────────────────────────────────

class _ResetAction extends StatelessWidget {
  const _ResetAction();

  @override
  Widget build(BuildContext context) {
    final theme = getIt<ThemeController>();
    if (theme.isDefault) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'appearance.reset_tooltip'.tr(),
      icon: const Icon(Icons.settings_backup_restore_rounded, size: 22),
      color: AppColors.textSecondary,
      onPressed: () {
        if (isMobilePlatform) HapticFeedback.selectionClick();
        theme.reset();
      },
    );
  }
}

class _ResetRow extends StatelessWidget {
  const _ResetRow({required this.enabled, required this.onReset});

  final bool enabled;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onReset : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
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
                    Icons.settings_backup_restore_rounded,
                    color: AppColors.textSecondary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'appearance.reset'.tr(),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Custom colour sheet ─────────────────────────────────────────────────────

/// Opens the custom accent picker. Returns the chosen colour, or null if the
/// sheet was dismissed.
Future<Color?> showCustomAccentSheet(
  BuildContext context, {
  required Color initial,
}) {
  return showModalBottomSheet<Color>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _CustomAccentSheet(initial: initial),
  );
}

class _CustomAccentSheet extends StatefulWidget {
  const _CustomAccentSheet({required this.initial});

  final Color initial;

  @override
  State<_CustomAccentSheet> createState() => _CustomAccentSheetState();
}

class _CustomAccentSheetState extends State<_CustomAccentSheet> {
  late HSLColor _hsl = HSLColor.fromColor(widget.initial);

  Color get _seed => _hsl.toColor();

  /// What the app would actually use — the seed after the white-legibility
  /// clamp. Showing both is what makes the clamp explicable instead of
  /// mysterious.
  AppAccent get _resolved => AppAccent.custom(_seed);

  bool get _wasAdjusted =>
      AppAccent.whiteContrast(_seed) < AppAccent.minWhiteContrast;

  void _update(HSLColor next) {
    setState(() => _hsl = next);
  }

  @override
  Widget build(BuildContext context) {
    final accent = _resolved;
    final hex = accent.base
        .toARGB32()
        .toRadixString(16)
        .padLeft(8, '0')
        .substring(2)
        .toUpperCase();

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.textHint.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'appearance.custom_title'.tr(),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '#$hex',
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 13,
                      fontFeatures: [FontFeature.tabularFigures()],
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // The candidate colour on the same surfaces the rest of the page
              // uses. DarknessSample takes an explicit palette, which is what
              // this needs — the colour being previewed is deliberately NOT the
              // one installed yet.
              Center(
                child: SizedBox(
                  width: 240,
                  child: DarknessSample(
                    palette: AppPalette.resolve(
                      accent: accent,
                      darkness: AppPalette.current.darkness,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              _GradientSlider(
                label: 'appearance.custom_hue'.tr(),
                value: _hsl.hue / 360,
                thumbColor: HSLColor.fromAHSL(1, _hsl.hue, 1, 0.5).toColor(),
                gradient: const [
                  Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00),
                  Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF),
                  Color(0xFFFF0000),
                ],
                onChanged: (t) => _update(_hsl.withHue((t * 360).clamp(0, 360))),
              ),
              const SizedBox(height: 14),
              _GradientSlider(
                label: 'appearance.custom_saturation'.tr(),
                value: _hsl.saturation,
                thumbColor: _seed,
                gradient: [
                  HSLColor.fromAHSL(1, _hsl.hue, 0, _hsl.lightness).toColor(),
                  HSLColor.fromAHSL(1, _hsl.hue, 1, _hsl.lightness).toColor(),
                ],
                onChanged: (t) => _update(_hsl.withSaturation(t)),
              ),
              const SizedBox(height: 14),
              _GradientSlider(
                label: 'appearance.custom_lightness'.tr(),
                value: _hsl.lightness,
                thumbColor: _seed,
                gradient: [
                  Colors.black,
                  HSLColor.fromAHSL(1, _hsl.hue, _hsl.saturation, 0.5).toColor(),
                  Colors.white,
                ],
                onChanged: (t) => _update(_hsl.withLightness(t)),
              ),

              if (_wasAdjusted) ...[
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 15,
                      color: AppColors.textHint,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'appearance.custom_adjusted'.tr(),
                        style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 46),
                        foregroundColor: AppColors.textSecondary,
                      ),
                      child: Text('general.cancel'.tr()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(_seed),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent.base,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 46),
                      ),
                      child: Text('appearance.custom_apply'.tr()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A gradient track with a draggable thumb, normalised to 0..1.
///
/// Hand-rolled rather than a themed [Slider] because the track *is* the
/// information here: it has to be a real gradient of the values it selects,
/// edge to edge, with the thumb sitting exactly on the colour it represents.
/// A Slider reserves invisible padding for its overlay, which would push the
/// gradient out of alignment with the thumb.
class _GradientSlider extends StatelessWidget {
  const _GradientSlider({
    required this.label,
    required this.value,
    required this.gradient,
    required this.thumbColor,
    required this.onChanged,
  });

  final String label;
  final double value;
  final List<Color> gradient;
  final Color thumbColor;
  final ValueChanged<double> onChanged;

  static const double _trackHeight = 14;
  static const double _thumbRadius = 12;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textHint,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            // The thumb's centre travels between the two inset edges, so the
            // track it walks along is shortened by one radius at each end.
            final usable = constraints.maxWidth - _thumbRadius * 2;
            void emit(double dx) {
              if (usable <= 0) return;
              onChanged(((dx - _thumbRadius) / usable).clamp(0.0, 1.0));
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => emit(d.localPosition.dx),
              onHorizontalDragStart: (d) => emit(d.localPosition.dx),
              onHorizontalDragUpdate: (d) => emit(d.localPosition.dx),
              child: SizedBox(
                height: _thumbRadius * 2 + 8,
                child: Stack(
                  alignment: AlignmentDirectional.centerStart,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: _thumbRadius,
                      ),
                      child: Container(
                        height: _trackHeight,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(_trackHeight / 2),
                          gradient: LinearGradient(colors: gradient),
                          border: Border.all(
                            color: AppColors.textPrimary.withValues(alpha: 0.10),
                            width: 0.5,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: usable.clamp(0, double.infinity) * value.clamp(0.0, 1.0),
                      child: Container(
                        width: _thumbRadius * 2,
                        height: _thumbRadius * 2,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: thumbColor,
                          border: Border.all(color: Colors.white, width: 2.5),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x66000000),
                              blurRadius: 5,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
