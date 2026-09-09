import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:soplay/features/download/domain/download_layout.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/download/domain/entities/download_kind.dart';

/// The filesystem, and the only place in the feature that knows where "here"
/// is on this launch.
///
/// The root is resolved once, in [initialize], and everything after that is a
/// synchronous string join. That is deliberate: [absoluteOf] is called from
/// build methods and tap handlers, and an async path lookup in either of those
/// is how the old code ended up storing the absolute path in the row "so it
/// would be there when we needed it" — which is the bug this whole change is
/// about.
class DownloadStorage {
  String? _root;
  String? _base;

  /// `<base>/downloads`. Throws if read before [initialize].
  String get root {
    final value = _root;
    if (value == null) {
      throw StateError('DownloadStorage.initialize() has not run');
    }
    return value;
  }

  /// The volume the downloads folder sits on — what a location setting picks.
  String get base => _base ?? '';

  bool get isReady => _root != null;

  /// Resolves the root, optionally on a volume the viewer chose.
  ///
  /// [preferredBase] is a path from the location setting. It is checked rather
  /// than trusted: an SD card that has been removed leaves a stored path that
  /// no longer exists, and falling back to the app's own directory is the
  /// difference between a library that looks empty and an app that cannot
  /// start its downloads at all.
  Future<void> initialize({String? preferredBase}) async {
    if (_root != null && preferredBase == null) return;

    var base = preferredBase?.trim();
    if (base != null && base.isNotEmpty) {
      try {
        final dir = Directory(base);
        if (!await dir.exists()) await dir.create(recursive: true);
        // Writable is not the same as present: a card mounted read-only, or a
        // path that survived an uninstall, both exist and neither can be
        // written to.
        final probe = File('$base/.sozo-write-test');
        await probe.writeAsString('1', flush: true);
        await probe.delete();
      } catch (e) {
        debugPrint('[downloads] chosen location unusable ($base): $e');
        base = null;
      }
    }
    base ??= (await getApplicationDocumentsDirectory()).path;

    final dir = Directory('$base/${DownloadLayout.root}');
    if (!await dir.exists()) await dir.create(recursive: true);
    _base = base;
    _root = dir.path;
  }

  /// The app's own directory, which is always writable and never chosen away.
  Future<String> defaultBase() async =>
      (await getApplicationDocumentsDirectory()).path;

  /// Moves the whole library to another volume.
  ///
  /// Copy-then-delete rather than `rename`: a rename across volumes fails on
  /// every platform, and this is only ever used to cross one. The source is
  /// deleted only after every file has arrived, so a failure half way costs
  /// disk space and nothing else — the downloads still play from where they
  /// were.
  Future<bool> moveTo(String newBase) async {
    final from = Directory(root);
    final target = Directory('$newBase/${DownloadLayout.root}');
    if (from.path == target.path) return true;

    try {
      if (!await target.exists()) await target.create(recursive: true);
      if (await from.exists()) {
        await for (final entity in from.list(recursive: true, followLinks: false)) {
          final relative = entity.path.substring(from.path.length + 1);
          final destination = '${target.path}/$relative';
          if (entity is Directory) {
            await Directory(destination).create(recursive: true);
          } else if (entity is File) {
            await Directory(destination.substring(0, destination.lastIndexOf('/')))
                .create(recursive: true);
            await entity.copy(destination);
          }
        }
        await from.delete(recursive: true);
      }
      _base = newBase;
      _root = target.path;
      return true;
    } catch (e) {
      debugPrint('[downloads] could not move the library: $e');
      return false;
    }
  }

  /// Resolves a stored relative path against this launch's root.
  ///
  /// Accepts an absolute path unchanged, so a row written by a build that
  /// predates the migration still opens on the device it was made on while
  /// the sweep repairs it.
  String absoluteOf(String relativePath) {
    if (relativePath.isEmpty) return '';
    if (relativePath.startsWith('/')) return relativePath;
    final trimmed = relativePath.startsWith('${DownloadLayout.root}/')
        ? relativePath.substring(DownloadLayout.root.length + 1)
        : relativePath;
    return '$root/$trimmed';
  }

  String dirOf(String id) => '$root/$id';

  Future<Directory> ensureDir(String id) async {
    final dir = Directory(dirOf(id));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Whether the artefact this row points at is actually there.
  ///
  /// A directory for a manga chapter, a non-empty file for anything else. The
  /// emptiness check matters: a transfer killed before its first buffer leaves
  /// a zero-byte file, which `exists()` alone reports as present and the
  /// player then opens onto a black screen.
  Future<bool> artefactExists(DownloadItem item) async {
    final path = absoluteOf(item.relativePath);
    if (path.isEmpty) return false;
    if (item.artefactIsDirectory) {
      final dir = Directory(path);
      if (!await dir.exists()) return false;
      return dir.list().any((e) => e is File);
    }
    final file = File(path);
    if (!await file.exists()) return false;
    return await file.length() > 0;
  }

  /// Repairs a row whose recorded artefact is not where it says.
  ///
  /// The layout is deterministic, so the only thing that can genuinely differ
  /// is a single-file video's extension — the source said `.mp4` and the host
  /// served an `.mkv`. Rather than fail such a download, look in its own
  /// folder for the one file that is obviously it.
  ///
  /// Returns the corrected relative path, or null when there is nothing to
  /// correct to.
  Future<String?> repairArtefactPath(DownloadItem item) async {
    if (item.artefactIsDirectory) return null;
    final dir = Directory(dirOf(item.id));
    if (!await dir.exists()) return null;

    File? candidate;
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        // A `.part` is an interrupted transfer, not the artefact.
        if (name.endsWith('.part')) continue;
        final matches = item.kind == DownloadKind.hls
            ? name == DownloadLayout.hlsIndexName
            : name.startsWith(DownloadLayout.videoStemName);
        if (!matches) continue;
        if (await entity.length() <= 0) continue;
        candidate = entity;
        break;
      }
    } catch (e) {
      debugPrint('[downloads] repair scan failed for ${item.id}: $e');
      return null;
    }
    if (candidate == null) return null;
    return '${DownloadLayout.dirFor(item.id)}/'
        '${candidate.uri.pathSegments.last}';
  }

  /// Everything the download occupies, folder and all.
  ///
  /// Measured rather than taken from the row: an HLS episode's size is the sum
  /// of its segments, and a cancelled transfer's `.part` counts against the
  /// device just as much as a finished file does.
  Future<int> sizeOf(String id) => _sizeOfDir(Directory(dirOf(id)));

  Future<int> totalSize() => _sizeOfDir(Directory(root));

  Future<int> _sizeOfDir(Directory dir) async {
    if (!await dir.exists()) return 0;
    var total = 0;
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {
            // A file deleted between the listing and the stat. Skipping it is
            // more honest than failing the whole measurement.
          }
        }
      }
    } catch (e) {
      debugPrint('[downloads] could not measure ${dir.path}: $e');
    }
    return total;
  }

  /// Folder ids under the root that no row claims.
  Future<List<String>> orphanIds(Set<String> knownIds) async {
    final dir = Directory(root);
    if (!await dir.exists()) return const [];
    final out = <String>[];
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final name = entity.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .last;
        if (!knownIds.contains(name)) out.add(name);
      }
    } catch (e) {
      debugPrint('[downloads] orphan scan failed: $e');
    }
    return out;
  }

  Future<void> deleteItem(String id) async {
    final dir = Directory(dirOf(id));
    if (await dir.exists()) {
      try {
        await dir.delete(recursive: true);
      } catch (e) {
        debugPrint('[downloads] could not delete $id: $e');
      }
    }
  }

  Future<void> deleteEverything() async {
    final dir = Directory(root);
    if (await dir.exists()) {
      try {
        await dir.delete(recursive: true);
      } catch (e) {
        debugPrint('[downloads] could not clear the folder: $e');
      }
    }
    await dir.create(recursive: true);
  }

  /// Free bytes on the volume the downloads live on, or 0 when it cannot be
  /// read.
  ///
  /// `statSync` on a directory does not carry free space, and Dart has no
  /// portable API for it. Android answers through the platform channel that
  /// already exists for the downloader; everywhere else this returns 0 and the
  /// UI omits the number rather than inventing one.
  Future<int> freeBytes(Future<int?> Function() platformProbe) async {
    try {
      return await platformProbe() ?? 0;
    } catch (e) {
      debugPrint('[downloads] free-space probe failed: $e');
      return 0;
    }
  }
}
