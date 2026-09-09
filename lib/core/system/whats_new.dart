import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:soplay/core/constants/app_constants.dart';

/// Marks features the viewer has not met yet.
///
/// ## The problem this solves
///
/// The app gains features faster than anyone reads a changelog, and they land
/// on a Profile page nine sections deep. Torrent search, the in-player source
/// switch, the Live TV guide and backup all shipped without a single surface
/// telling an existing user they now exist. A feature nobody finds may as well
/// not have been built.
///
/// ## Why versions rather than a "seen" set
///
/// A plain set of seen ids would mark *everything* new for a fresh install —
/// and for an existing user's first launch after this ships, since neither has
/// a set yet. Recording the version last seen distinguishes the two: a first
/// run stamps the current version and shows nothing, so only a real upgrade
/// past a feature's version lights it up.
abstract final class WhatsNew {
  /// Feature id → the version it first shipped in.
  ///
  /// Ids are stable strings, not enum indices: they end up in stored state and
  /// must survive reordering. Add a row here when a feature lands; there is
  /// nothing else to wire.
  static const Map<String, String> features = {
    // Landing together in the next build. Every one of these is somewhere in
    // Profile that nobody has a reason to open unprompted.
    'stats': '3.0.4',
    'home_rails': '3.0.4',
    'relations': '3.0.4',
    'shaders': '3.0.4',
    'torrents': '3.0.3',
    'change_source': '3.0.3',
    'live_guide': '3.0.3',
    'episode_downloads': '3.0.3',
    'backup': '3.0.2',
    'voice_search': '3.0.2',
    'sleep_timer': '3.0.2',
  };

  static Box get _box => Hive.box(AppConstants.settingsBox);

  /// Bumped whenever a badge is cleared.
  ///
  /// Badges appear on rows that are stateless, and on the parent rows above
  /// them — a dot on Profile has to disappear when the last thing behind it is
  /// opened. One notifier the whole tree can listen to is what makes that
  /// happen without threading callbacks through five levels.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static String _current = '';

  /// Resolves the running version and, on a first run, stamps it so nothing is
  /// announced to someone who has never seen the old build.
  ///
  /// Safe to call more than once and never throws: a failure here must not stop
  /// the app, it just means no badges.
  static Future<void> init() async {
    try {
      _current = (await PackageInfo.fromPlatform()).version;
      if (lastSeenVersion.isEmpty) {
        await _box.put(AppConstants.whatsNewVersionKey, _current);
      }
    } catch (_) {
      _current = '';
    }
  }

  static String get lastSeenVersion =>
      _box.get(AppConstants.whatsNewVersionKey, defaultValue: '') as String;

  static Set<String> get _dismissed =>
      ((_box.get(AppConstants.whatsNewSeenKey) as List?) ?? const [])
          .map((e) => e.toString())
          .toSet();

  /// Whether [id] is worth pointing at for this viewer.
  static bool isNew(String id) {
    final introduced = features[id];
    if (introduced == null) return false;
    if (_dismissed.contains(id)) return false;
    final seen = lastSeenVersion;
    // No stamp yet means init() has not run; say nothing rather than guess.
    if (seen.isEmpty) return false;
    return _compare(introduced, seen) > 0;
  }

  /// True when anything in [ids] is new — for the dot on a parent row, so the
  /// badge is visible from the top level instead of only after you have already
  /// found the thing.
  static bool anyNew(Iterable<String> ids) => ids.any(isNew);

  /// Called when the viewer opens the feature. One id at a time, because
  /// opening a section should not silently clear badges further in.
  static Future<void> markSeen(String id) async {
    if (!features.containsKey(id)) return;
    final seen = _dismissed..add(id);
    await _box.put(AppConstants.whatsNewSeenKey, seen.toList());
    revision.value++;
  }

  /// Clears every badge and moves the stamp to the running version. For a
  /// "mark all as read" affordance.
  static Future<void> markAllSeen() async {
    await _box.put(AppConstants.whatsNewSeenKey, features.keys.toList());
    if (_current.isNotEmpty) {
      await _box.put(AppConstants.whatsNewVersionKey, _current);
    }
    revision.value++;
  }

  /// Dotted version compare — `3.0.10` is above `3.0.9`, which a string
  /// comparison gets backwards. Missing or non-numeric parts count as zero, so
  /// a malformed version degrades to "not newer" rather than throwing.
  static int _compare(String a, String b) {
    final x = a.split('.');
    final y = b.split('.');
    for (var i = 0; i < 3; i++) {
      final ai = i < x.length ? int.tryParse(x[i].trim()) ?? 0 : 0;
      final bi = i < y.length ? int.tryParse(y[i].trim()) ?? 0 : 0;
      if (ai != bi) return ai.compareTo(bi);
    }
    return 0;
  }
}
