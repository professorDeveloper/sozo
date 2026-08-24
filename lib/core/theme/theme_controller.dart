import 'package:flutter/material.dart';
import 'package:soplay/core/storage/hive_service.dart';

import 'app_accent.dart';
import 'app_palette.dart';

/// Owns everything Settings → Appearance can change: the accent colour and how
/// dark the neutrals go.
///
/// ## How a change reaches the whole app
///
/// Almost every widget in Sozo reads a colour as `AppColors.primary` — a static
/// getter, with no `BuildContext` and therefore no `InheritedWidget` to depend
/// on. So a theme change is two separate jobs, and this class does the first:
///
///   1. **here** — swap [AppPalette.current], persist, then `notifyListeners()`,
///   2. **`MyApp`** — hand `MaterialApp` a freshly built [ThemeData] *and* mark
///      every element in the tree dirty, so the static readers repaint too.
///
/// Splitting it that way is what keeps the change instant and total: no restart,
/// no route rebuild, no lost navigation stack or scroll position.
///
/// The constructor loads and applies synchronously, before `runApp`, so the very
/// first frame is already painted in the user's colours — there is never a flash
/// of red before a blue theme appears.
class ThemeController extends ChangeNotifier {
  ThemeController(this._hive) {
    _accent = _readAccent();
    _darkness = _hive.isAmoledMode ? AppDarkness.black : AppDarkness.dark;
    _tintNav = _hive.isNavTinted;
    _apply();
  }

  final HiveService _hive;

  late AppAccent _accent;
  late AppDarkness _darkness;
  late bool _tintNav;

  AppAccent get accent => _accent;
  AppDarkness get darkness => _darkness;

  /// Whether the bottom bar's selected tab carries the accent.
  bool get isNavTinted => _tintNav;

  /// True while the neutrals are true black.
  bool get isAmoled => _darkness == AppDarkness.black;

  /// The id to tick in the swatch row. For a custom colour this is
  /// [AppAccent.customId], not the nearest preset.
  String get accentId => _accent.id;

  /// Everything is at its shipped value — what the "Reset" action undoes.
  ///
  /// The tab-bar tint ships **on**, so "default" means on here.
  bool get isDefault =>
      _accent.id == AppAccent.fallback.id &&
      _darkness == AppDarkness.dark &&
      _tintNav;

  AppAccent _readAccent() {
    final id = _hive.accentId;
    if (id == AppAccent.customId) {
      final argb = _hive.customAccentArgb;
      // A stored custom id with no stored colour is a half-written preference;
      // fall back rather than paint an arbitrary colour.
      if (argb != null) return AppAccent.custom(Color(argb));
      return AppAccent.fallback;
    }
    return AppAccent.byId(id) ?? AppAccent.fallback;
  }

  void _apply() {
    AppPalette.current = AppPalette.resolve(
      accent: _accent,
      darkness: _darkness,
      tintNav: _tintNav,
    );
  }

  /// Pick one of the [AppAccent.presets].
  Future<void> setAccent(AppAccent accent) async {
    if (accent.id == _accent.id && accent.base == _accent.base) return;
    _accent = accent;
    _apply();
    notifyListeners();
    await _hive.setAccentId(accent.id);
  }

  /// Pick an arbitrary colour. [seed] is normalised by [AppAccent.custom] so
  /// white stays legible on it; the *seed* is what gets persisted, so re-opening
  /// the picker shows the wheel where the user left it rather than where the
  /// contract moved it.
  Future<void> setCustomAccent(Color seed) async {
    final accent = AppAccent.custom(seed);
    _accent = accent;
    _apply();
    notifyListeners();
    await _hive.setCustomAccentArgb(seed.withValues(alpha: 1.0).toARGB32());
    await _hive.setAccentId(AppAccent.customId);
  }

  /// The seed behind a custom accent, for re-opening the picker on the colour
  /// the user actually chose. Null unless the current accent is custom.
  Color? get customSeed {
    if (!_accent.isCustom) return null;
    final argb = _hive.customAccentArgb;
    return argb == null ? null : Color(argb);
  }

  Future<void> setAmoled(bool enabled) async {
    final next = enabled ? AppDarkness.black : AppDarkness.dark;
    if (next == _darkness) return;
    _darkness = next;
    _apply();
    notifyListeners();
    await _hive.setAmoledMode(enabled);
  }

  Future<void> toggleAmoled() => setAmoled(!isAmoled);

  Future<void> setNavTinted(bool enabled) async {
    if (enabled == _tintNav) return;
    _tintNav = enabled;
    _apply();
    notifyListeners();
    await _hive.setNavTinted(enabled);
  }

  /// Jump to a preset the user is not already on.
  ///
  /// Deterministic rather than random: [step] walks the ring, so tapping it
  /// repeatedly tours the palette instead of landing on the same colour twice
  /// in a row the way `Random` eventually does.
  Future<void> cycleAccent({int step = 1}) async {
    final presets = AppAccent.presets;
    final at = presets.indexWhere((a) => a.id == _accent.id);
    // A custom accent is not on the ring, so stepping starts from the default.
    final next = ((at < 0 ? -1 : at) + step) % presets.length;
    await setAccent(presets[next < 0 ? next + presets.length : next]);
  }

  /// Back to the shipped look: default red, ordinary dark greys.
  Future<void> reset() async {
    if (isDefault) return;
    _accent = AppAccent.fallback;
    _darkness = AppDarkness.dark;
    _tintNav = true;
    _apply();
    notifyListeners();
    await _hive.setAccentId(AppAccent.fallback.id);
    await _hive.setAmoledMode(false);
    await _hive.setNavTinted(true);
  }
}
