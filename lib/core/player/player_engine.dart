import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/system/platform_utils.dart';

/// Playback backend for the in-app player.
///
/// Only ever chosen by the user on Android. Desktop is pinned to [mediaKit]
/// (libmpv is the only backend that exists there) and iOS is pinned to
/// [native] — `media_kit_libs_ios_video` is deliberately not a dependency, so
/// there is no libmpv to fall back to on that platform.
enum PlayerEngine {
  /// `video_player` — ExoPlayer on Android. The platform player: best battery
  /// life and hardware decoding, but no audio-track switching, because the
  /// platform API simply does not expose them. Was the shipped default until
  /// [AppConstants.defaultPlayerEngine] moved to media_kit; the id stays
  /// `'default'` because it is persisted in Hive and renaming it would reset
  /// every install that chose it.
  native('default'),

  /// `media_kit` — libmpv. Exposes audio and subtitle track selection.
  mediaKit('media_kit'),

  /// Hand the stream off to VLC / MX Player via an ACTION_VIEW intent.
  /// Playback leaves the app entirely, so no in-app controls apply.
  external('external');

  const PlayerEngine(this.id);

  /// Stable string persisted in Hive. Never renumber or reorder — the stored
  /// value outlives the enum's index.
  final String id;

  /// The engine an install with no stored choice gets.
  ///
  /// Derived, never written down twice. The badge in Settings marks whichever
  /// engine this is, so moving the default cannot leave the label behind on
  /// the old one.
  static PlayerEngine get defaultEngine =>
      fromId(AppConstants.defaultPlayerEngine);

  static PlayerEngine fromId(String? id) {
    for (final e in PlayerEngine.values) {
      if (e.id == id) return e;
    }
    return PlayerEngine.native;
  }
}

/// Set when libmpv could not be loaded on this device.
///
/// Not persisted, and deliberately so. A failed load is a property of the
/// device or the build — a missing ABI, a stripped library — so retrying costs
/// one cheap load attempt per launch, and that is the whole downside. Writing
/// the fallback to Hive instead would silently rewrite a setting the user
/// chose, and it would keep them on the platform player forever after a
/// failure that a later app update fixes.
bool _mediaKitUnavailable = false;

/// Report that libmpv will not load, so nothing tries it again this session.
void markMediaKitUnavailable() => _mediaKitUnavailable = true;

@visibleForTesting
void resetMediaKitAvailability() => _mediaKitUnavailable = false;

/// The engine that should actually be used right now.
///
/// Reads Hive on every call rather than caching, so flipping the setting takes
/// effect on the very next playback with no app restart. The read is an
/// in-memory map lookup on an already-open box — cheap enough to call per load.
///
/// Falls back to [PlayerEngine.native] if the box is not open (unit tests, or
/// any call before `_initHive`), which is the pre-existing behaviour.
PlayerEngine resolvePlayerEngine() {
  // Desktop has no native backend at all; iOS has no libmpv. Neither platform
  // is user-selectable, so don't even look at the stored value there.
  if (isDesktopPlatform) {
    // Desktop genuinely has nothing else, so a failed load there is fatal
    // either way and pretending otherwise would only hide it.
    return PlayerEngine.mediaKit;
  }
  if (kIsWeb || !Platform.isAndroid) return PlayerEngine.native;
  PlayerEngine chosen;
  try {
    final box = Hive.box(AppConstants.settingsBox);
    chosen = PlayerEngine.fromId(
      box.get(
        AppConstants.playerEngineKey,
        defaultValue: AppConstants.defaultPlayerEngine,
      ) as String?,
    );
  } catch (_) {
    return PlayerEngine.native;
  }
  // Answers what will actually run, not what is stored. The stored preference
  // stays media_kit — Settings reads Hive directly and still shows the user's
  // own choice — but every playback path asks this, and handing them an engine
  // that cannot start is a black screen with no way out of it.
  if (chosen == PlayerEngine.mediaKit && _mediaKitUnavailable) {
    return PlayerEngine.native;
  }
  return chosen;
}

/// Whether the engine picker should be offered at all. Android-only: every
/// other platform is pinned, so showing the control would be a lie.
bool get canChoosePlayerEngine =>
    !kIsWeb && Platform.isAndroid && !isDesktopPlatform;
