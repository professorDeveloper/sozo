import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'package:soplay/core/constants/app_constants.dart';

/// What a restore actually changed, so the user is told rather than reassured.
class BackupSummary {
  const BackupSummary({
    required this.restored,
    required this.skipped,
    this.error,
  });

  final int restored;
  final int skipped;
  final String? error;

  bool get ok => error == null;
}

/// Export and restore of everything the app knows about a viewer.
///
/// The thing this protects against is mundane and total: a reinstall, a new
/// phone, a cleared app. Watch history, lists, installed extension repos and
/// every setting live only on the device, and until now all of it went with the
/// app.
///
/// ## What is included, and what is not
///
/// The auth box is excluded in full. It holds the session token and the AniList
/// and MAL tokens, and those are credentials — writing them into a file the
/// user is about to send through a messenger to themselves would turn a backup
/// into a way to lose an account. Signing in again is the cheap half of
/// restoring; the AniList *links* — which local title maps to which media id —
/// are the expensive half, and those are ordinary data that comes along.
///
/// Downloads are excluded because they are paths to files on the old device,
/// and extractors because they are a cache the app refills on demand. Neither
/// means anything on the machine being restored to.
///
/// ## Merge, not replace
///
/// A restore writes the keys the file contains and leaves everything else
/// alone. Wiping first would be the more obvious implementation and the worse
/// one: restoring a six-month-old backup would silently delete everything
/// watched since, which is the opposite of what someone reaching for a backup
/// wants.
class BackupService {
  static const String _tag = '[backup]';

  /// Marks the file as ours and lets a future format change be rejected
  /// politely instead of half-applied.
  static const String formatId = 'sozo.backup';
  static const int formatVersion = 1;

  /// Boxes worth carrying to another device.
  static const List<String> _boxes = [
    AppConstants.settingsBox,
    AppConstants.historyBox,
    AppConstants.favoritesBox,
    AppConstants.privateFavoritesBox,
    AppConstants.userListsBox,
    AppConstants.streakBox,
  ];

  /// Settings that are caches or device-local, and would be wrong elsewhere.
  ///
  /// The provider cache is refetched on launch and a stale copy restored onto a
  /// new device would show sources that have since been removed. The bridge url
  /// points at a machine on the old network.
  static const Set<String> _settingsDenyList = {
    AppConstants.cachedProvidersKey,
    AppConstants.cachedProvidersAtKey,
    AppConstants.lastBackupAtKey,
    'desktop_bridge_url',
  };

  /// Write a backup and return the file.
  Future<File> export() async {
    final boxes = <String, Map<String, dynamic>>{};
    var skipped = 0;

    for (final name in _boxes) {
      if (!Hive.isBoxOpen(name)) continue;
      final box = Hive.box(name);
      final out = <String, dynamic>{};
      for (final key in box.keys) {
        if (name == AppConstants.settingsBox &&
            _settingsDenyList.contains('$key')) {
          continue;
        }
        final value = box.get(key);
        // Hive holds whatever it was given. Anything that will not survive a
        // JSON round trip is dropped rather than allowed to abort the whole
        // export — one unencodable setting should not cost someone their
        // history.
        try {
          jsonEncode(value);
          out['$key'] = value;
        } catch (_) {
          skipped++;
        }
      }
      boxes[name] = out;
    }

    final payload = <String, dynamic>{
      'format': formatId,
      'version': formatVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'boxes': boxes,
    };

    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File('${dir.path}/sozo-backup-$stamp.json');
    await file.writeAsString(jsonEncode(payload));
    await _rememberExport();
    debugPrint('$_tag exported ${boxes.length} boxes, $skipped values skipped');
    return file;
  }

  /// The moment of the last successful export, or null if this device has
  /// never made one.
  DateTime? get lastExportAt {
    try {
      final raw = Hive.box(
        AppConstants.settingsBox,
      ).get(AppConstants.lastBackupAtKey);
      if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    } catch (_) {}
    return null;
  }

  Future<void> _rememberExport() async {
    try {
      await Hive.box(AppConstants.settingsBox).put(
        AppConstants.lastBackupAtKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  /// Restore from a file written by [export].
  Future<BackupSummary> import(File file) async {
    final Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return const BackupSummary(
          restored: 0,
          skipped: 0,
          error: 'not_a_backup',
        );
      }
      payload = decoded;
    } catch (_) {
      return const BackupSummary(restored: 0, skipped: 0, error: 'not_a_backup');
    }

    if (payload['format'] != formatId) {
      return const BackupSummary(restored: 0, skipped: 0, error: 'not_a_backup');
    }
    final version = (payload['version'] as num?)?.toInt() ?? 0;
    if (version > formatVersion) {
      // Written by a newer build. Refusing is the honest answer: applying only
      // the parts we recognise would leave a half-restored device that looks
      // restored.
      return const BackupSummary(restored: 0, skipped: 0, error: 'too_new');
    }

    final boxes = payload['boxes'];
    if (boxes is! Map) {
      return const BackupSummary(restored: 0, skipped: 0, error: 'not_a_backup');
    }

    var restored = 0;
    var skipped = 0;
    for (final entry in boxes.entries) {
      final name = '${entry.key}';
      // Only boxes this build knows and has open. A backup naming something
      // else is either from a newer version or corrupt, and opening a box by a
      // name from a file is not something to do on a user's behalf.
      if (!_boxes.contains(name) || !Hive.isBoxOpen(name)) {
        skipped++;
        continue;
      }
      final values = entry.value;
      if (values is! Map) {
        skipped++;
        continue;
      }
      final box = Hive.box(name);
      for (final kv in values.entries) {
        final key = '${kv.key}';
        if (name == AppConstants.settingsBox &&
            _settingsDenyList.contains(key)) {
          continue;
        }
        try {
          await box.put(key, kv.value);
          restored++;
        } catch (_) {
          skipped++;
        }
      }
    }

    debugPrint('$_tag restored $restored values, $skipped skipped');
    return BackupSummary(restored: restored, skipped: skipped);
  }
}
