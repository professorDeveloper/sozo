import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/box_recovery.dart';
import 'package:soplay/core/storage/profile_scope.dart';
import 'package:soplay/core/storage/secure_boxes.dart';

/// Opens and removes the boxes of the extra (non-default) profiles.
///
/// The default profile's boxes are opened by `_initHive` like they always
/// were; this never touches them.
class ProfileStorage {
  ProfileStorage._();

  /// Where Hive keeps its files, for [BoxRecovery]. Null in tests.
  static String? directory;

  static Future<void> open(String? namespace) async {
    if (namespace == null) return;
    HiveAesCipher? cipher;
    var cipherLoaded = false;
    for (final base in ProfileScope.profileBoxes) {
      final name = ProfileScope.boxFor(base, namespace);
      if (Hive.isBoxOpen(name)) continue;
      if (base == AppConstants.privateFavoritesBox) {
        if (!cipherLoaded) {
          cipher = await SecureBoxes.cipher();
          cipherLoaded = true;
        }
        try {
          await SecureBoxes.open(name, cipher);
        } catch (e) {
          debugPrint('[ProfileStorage] $name: unopenable, in memory: $e');
          await Hive.openBox(name, bytes: Uint8List(0));
        }
      } else {
        await BoxRecovery.open(name, directory: directory);
      }
    }
  }

  /// Deletes one extra profile's boxes and settings keys from this device.
  static Future<void> delete(String namespace, Box settings) async {
    for (final base in ProfileScope.profileBoxes) {
      final name = ProfileScope.boxFor(base, namespace);
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (e) {
        debugPrint('[ProfileStorage] $name: delete failed: $e');
      }
    }
    final suffix = '@p_$namespace';
    final keys = settings.keys
        .where((k) => k is String && k.endsWith(suffix))
        .toList();
    if (keys.isNotEmpty) await settings.deleteAll(keys);
  }

  /// Every extra profile's private list. They are all behind the one device
  /// PIN, so resetting that PIN has to take all of them, not just the active
  /// profile's.
  static Future<void> clearPrivateLists() async {
    for (final ns in _namespacesOnDisk()) {
      final name = ProfileScope.boxFor(AppConstants.privateFavoritesBox, ns);
      try {
        if (Hive.isBoxOpen(name)) {
          await Hive.box(name).clear();
        } else {
          await Hive.deleteBoxFromDisk(name);
        }
      } catch (e) {
        debugPrint('[ProfileStorage] $name: wipe failed: $e');
      }
    }
  }

  static Set<String> _namespacesOnDisk() {
    final out = <String>{};
    final dir = directory;
    if (dir == null) return out;
    try {
      for (final entry in Directory(dir).listSync()) {
        final file = entry.uri.pathSegments.last;
        if (!file.endsWith('.hive')) continue;
        final at = file.indexOf('__p_');
        if (at < 0) continue;
        out.add(file.substring(at + 4, file.length - 5));
      }
    } catch (e) {
      debugPrint('[ProfileStorage] listing $dir failed: $e');
    }
    return out;
  }

  /// Every extra profile's data, for sign-out. Found on disk rather than from
  /// the cached list, which may no longer name a profile deleted elsewhere.
  static Future<void> deleteAll(
    Box settings, {
    Iterable<String> known = const [],
  }) async {
    final namespaces = {...known, ..._namespacesOnDisk()};
    for (final ns in namespaces) {
      await delete(ns, settings);
    }
    final keys = settings.keys.where(ProfileScope.isProfileKey).toList();
    if (keys.isNotEmpty) await settings.deleteAll(keys);
  }
}
