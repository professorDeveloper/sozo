import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/profile_scope.dart';
import 'package:soplay/features/profile/data/extension_backup.dart';
import 'package:soplay/features/profiles/data/profile_session.dart';

/// What a restore actually changed, so the user is told rather than reassured.
class BackupSummary {
  const BackupSummary({
    required this.restored,
    required this.skipped,
    this.error,
    this.extensions = ExtensionRestoreReport.empty,
    this.from,
  });

  final int restored;
  final int skipped;
  final String? error;

  /// What happened to the sources, which a restore reinstalls from their
  /// repos rather than from the file.
  final ExtensionRestoreReport extensions;

  /// The manifest the file was written with, for saying which device and
  /// version it came from. Null for a version 1 file, which had none.
  final Map<String, dynamic>? from;

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

  /// 2 added the manifest and the native extension systems. A version 1 file
  /// still restores: it simply has neither.
  static const int formatVersion = 2;

  BackupService({ExtensionBackup? extensions})
    : _extensions = extensions ?? ExtensionBackup();

  final ExtensionBackup _extensions;

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
    // This device's wallpaper colour, not a choice: the new device has its own.
    AppConstants.systemAccentKey,
    // Writes queued for a tracker account, due on this device. Replayed on
    // another they would be old news sent twice.
    AppConstants.trackerOutboxKey,
    // Which household profile this device acts as; the account decides that.
    ProfileSession.cacheKey,
    ProfileSession.activeKey,
  };

  /// The file always holds one person's data under the plain names, so it
  /// restores into whichever profile is active when it is read back.
  static Iterable<(String, String)> _settingsKeys(Box box) sync* {
    for (final key in box.keys) {
      final k = '$key';
      if (_settingsDenyList.contains(k) ||
          ProfileScope.isProfileKey(k) ||
          ProfileScope.profileKeys.contains(k)) {
        continue;
      }
      yield (k, k);
    }
    for (final k in ProfileScope.profileKeys) {
      final stored = ProfileScope.key(k);
      if (box.containsKey(stored)) yield (k, stored);
    }
  }

  /// Write a backup and return the file.
  Future<File> export() async {
    final boxes = <String, Map<String, dynamic>>{};
    var skipped = 0;

    for (final name in _boxes) {
      final actual = ProfileScope.box(name);
      if (!Hive.isBoxOpen(actual)) continue;
      final box = Hive.box(actual);
      final out = <String, dynamic>{};
      final keys = name == AppConstants.settingsBox
          ? _settingsKeys(box)
          : box.keys.map((k) => ('$k', k));
      for (final (key, stored) in keys) {
        final value = box.get(stored);
        // Hive holds whatever it was given. Anything that will not survive a
        // JSON round trip is dropped rather than allowed to abort the whole
        // export — one unencodable setting should not cost someone their
        // history.
        try {
          jsonEncode(value);
          out[key] = value;
        } catch (_) {
          skipped++;
        }
      }
      boxes[name] = out;
    }

    Map<String, dynamic> extensions = const {};
    try {
      extensions = await _extensions.export();
    } catch (e) {
      debugPrint('$_tag extensions skipped: $e');
    }

    final payload = <String, dynamic>{
      'format': formatId,
      'version': formatVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'manifest': await _manifest(boxes, extensions),
      'boxes': boxes,
      if (extensions.isNotEmpty) 'extensions': extensions,
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

  /// What the file holds and where it came from, readable without restoring
  /// it — and what a restore reports back.
  Future<Map<String, dynamic>> _manifest(
    Map<String, Map<String, dynamic>> boxes,
    Map<String, dynamic> extensions,
  ) async {
    String? app;
    try {
      final info = await PackageInfo.fromPlatform();
      app = '${info.version}+${info.buildNumber}';
    } catch (_) {}
    return {
      'app': ?app,
      'platform': defaultTargetPlatform.name,
      'boxes': {for (final e in boxes.entries) e.key: e.value.length},
      'extensions': ExtensionBackup.count(extensions),
    };
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
  ///
  /// Settings and lists first, then the sources — which means reaching each
  /// repo over the network, so it is the slow half and the one most likely to
  /// come back partial. [onExtensions] says when that half starts.
  Future<BackupSummary> import(
    File file, {
    void Function(String hostId)? onExtensions,
  }) async {
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
      return const BackupSummary(
        restored: 0,
        skipped: 0,
        error: 'not_a_backup',
      );
    }

    if (payload['format'] != formatId) {
      return const BackupSummary(
        restored: 0,
        skipped: 0,
        error: 'not_a_backup',
      );
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
      return const BackupSummary(
        restored: 0,
        skipped: 0,
        error: 'not_a_backup',
      );
    }

    var restored = 0;
    var skipped = 0;
    for (final entry in boxes.entries) {
      final name = '${entry.key}';
      // Only boxes this build knows and has open. A backup naming something
      // else is either from a newer version or corrupt, and opening a box by a
      // name from a file is not something to do on a user's behalf.
      final actual = ProfileScope.box(name);
      if (!_boxes.contains(name) || !Hive.isBoxOpen(actual)) {
        skipped++;
        continue;
      }
      final values = entry.value;
      if (values is! Map) {
        skipped++;
        continue;
      }
      final box = Hive.box(actual);
      final settings = name == AppConstants.settingsBox;
      for (final kv in values.entries) {
        final key = '${kv.key}';
        if (settings &&
            (_settingsDenyList.contains(key) ||
                ProfileScope.isProfileKey(key))) {
          continue;
        }
        try {
          await box.put(settings ? ProfileScope.key(key) : key, kv.value);
          restored++;
        } catch (_) {
          skipped++;
        }
      }
    }

    var extensions = ExtensionRestoreReport.empty;
    final ext = payload['extensions'];
    if (ext is Map<String, dynamic>) {
      extensions = await _extensions.restore(ext, onHost: onExtensions);
    }

    debugPrint(
      '$_tag restored $restored values, $skipped skipped; '
      '${extensions.reposAdded} repos, '
      '${extensions.missingSources.length} sources missing',
    );
    final manifest = payload['manifest'];
    return BackupSummary(
      restored: restored,
      skipped: skipped,
      extensions: extensions,
      from: manifest is Map<String, dynamic> ? manifest : null,
    );
  }
}
