import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';

/// Spoiler and timed-reaction preferences.
///
/// Best-effort like the other small stores: with no box (widget tests, the
/// moments before Hive opens) every getter answers its default.
class SocialPlaybackPrefs {
  const SocialPlaybackPrefs();

  static const String _hideSpoilersKey = 'hide_unwatched_spoilers';
  static const String _reactionsOverlayKey = 'timed_reactions_overlay';

  Box? get _box {
    try {
      return Hive.box(AppConstants.settingsBox);
    } catch (_) {
      return null;
    }
  }

  /// Hide comments about episodes the viewer has not finished. On by default.
  bool get hideUnwatchedSpoilers =>
      _box?.get(_hideSpoilersKey, defaultValue: true) != false;

  Future<void> setHideUnwatchedSpoilers(bool value) async {
    await _box?.put(_hideSpoilersKey, value);
  }

  /// Other viewers' reactions over the video. On by default.
  bool get reactionsOverlay =>
      _box?.get(_reactionsOverlayKey, defaultValue: true) != false;

  Future<void> setReactionsOverlay(bool value) async {
    await _box?.put(_reactionsOverlayKey, value);
  }
}
