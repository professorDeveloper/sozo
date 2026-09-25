import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Opens a Hive box without ever silently throwing the user's data away, and
/// without a single unreadable file being able to stop the app from starting.
///
/// Two separate faults, both of them live:
///
/// **Hive's default is to truncate.** `crashRecovery` is on unless you say
/// otherwise, and what it does on a bad checksum is `truncate(recoveryOffset)`
/// — the file is rewritten up to the last frame it could read, and everything
/// after it is gone from disk. For a torn tail that is exactly right. For a file
/// whose damage is near the front it is the whole box, and the only trace is a
/// `print('Recovering corrupted box.')` on a console nobody is attached to. On a
/// phone that reads as history, resume positions, My List and the downloads
/// index having quietly emptied themselves.
///
/// **One bad file took the whole launch.** Every box was opened by a bare
/// `Hive.openBox` inside one `Future.wait`, before `runApp`, so a file the
/// filesystem would not hand over meant a blank screen with no message and no
/// way out but clearing the app's data — which throws away the eight boxes that
/// were fine along with the one that was not.
///
/// So the read happens twice, deliberately. First with recovery OFF, which turns
/// "I am about to overwrite this" into an exception. If it throws, the file is
/// copied aside — copied, not moved, so the original is still there to be
/// recovered from — and only then reopened with recovery ON, which keeps every
/// frame up to the damage. The user gets back as much as Hive can read, the rest
/// is still on disk under a name that says what it is, and nothing was deleted
/// to achieve either.
///
/// The last resort is a box with no file behind it at all: writes go nowhere,
/// reads answer empty, the app starts. A session with an empty history is worth
/// having; a session that never starts is not.
class BoxRecovery {
  BoxRecovery._();

  /// The suffix a preserved file gets. Deliberately not `.bak`: this is not a
  /// backup the app made on purpose, it is evidence.
  static const String suffix = '.unreadable';

  static final List<String> _damaged = <String>[];

  /// Boxes whose file turned out to be damaged this launch, in the order it
  /// happened.
  ///
  /// Worth surfacing: a history that is suddenly short, with no explanation,
  /// reads as a bug in the app rather than as a file that got hurt.
  static List<String> get damaged => List.unmodifiable(_damaged);

  @visibleForTesting
  static void resetForTest() => _damaged.clear();

  /// Opens [name], falling back rather than throwing.
  ///
  /// [directory] is where Hive was initialised — it exposes no way to ask. With
  /// null, a damaged file cannot be preserved, so recovery is skipped and the
  /// box opens in memory instead; that is the shape a test wants, never
  /// production.
  static Future<Box<dynamic>> open(String name, {String? directory}) async {
    // Recovery off: a bad checksum is reported instead of being written over.
    final clean = await _attempt(name, recovery: false);
    if (clean != null) return clean;
    await _close(name);
    if (directory != null) {
      final kept = await preserve(name, directory);
      if (kept) _damaged.add(name);
      // Now that the original is safe, let Hive keep what it can.
      final recovered = await _attempt(name, recovery: true);
      if (recovered != null) return recovered;
      await _close(name);
      // Nothing readable in it at all. Start from empty rather than not at all —
      // the copy above is what makes that affordable.
      if (kept) {
        await _remove(name, directory);
        final fresh = await _attempt(name, recovery: true);
        if (fresh != null) return fresh;
      }
    }
    await _close(name);
    return Hive.openBox(name, bytes: Uint8List(0));
  }

  /// One open attempt, or null if it failed.
  ///
  /// Forks a zone for it because Hive reports a failed open TWICE: once to the
  /// caller, which is the half this class handles, and once as an orphan — it
  /// completes an internal completer that nobody listens to with the same error,
  /// so a failure this method deals with cleanly still arrives at the app's
  /// top-level error handler as if nothing had caught it. Under
  /// `FlutterError.onError` that is a Crashlytics report for a handled
  /// condition; under `flutter_test` it fails a passing test.
  ///
  /// Only that orphan is dropped. Anything the box reports later — a compaction
  /// that fails on a full disk, say — is forwarded to the zone this was called
  /// from, which is where it would have gone.
  static Future<Box<dynamic>?> _attempt(String name, {required bool recovery}) {
    final parent = Zone.current;
    final done = Completer<Box<dynamic>?>();
    Object? caught;
    var attempting = true;
    runZonedGuarded(
      () async {
        Box<dynamic>? box;
        try {
          box = await Hive.openBox(name, crashRecovery: recovery);
        } catch (e) {
          caught = e;
          debugPrint('[BoxRecovery] $name: open failed: $e');
        }
        attempting = false;
        if (!done.isCompleted) done.complete(box);
      },
      (error, stack) {
        if (attempting || identical(error, caught)) return;
        parent.handleUncaughtError(error, stack);
      },
    );
    return done.future;
  }

  /// Copies [name]'s file to `<file>.unreadable`, returning whether it did.
  ///
  /// An existing copy is never overwritten: the first one is the one that still
  /// had the user's data in it, and a second bad launch would replace it with
  /// whatever the app has managed to write since.
  static Future<bool> preserve(String name, String directory) async {
    final file = _file(name, directory, '.hive');
    if (!await file.exists()) return false;
    final target = File('${file.path}$suffix');
    try {
      if (await target.exists()) return true;
      await file.copy(target.path);
      debugPrint('[BoxRecovery] $name: kept a copy at ${target.path}');
      return true;
    } catch (e) {
      debugPrint('[BoxRecovery] $name: could not keep a copy: $e');
      return false;
    }
  }

  /// Deletes the live files for [name], leaving any `.unreadable` copy alone.
  ///
  /// Only ever called once [preserve] has said the data is safe somewhere else.
  static Future<void> _remove(String name, String directory) async {
    for (final ext in const ['.hive', '.hivec', '.lock']) {
      final file = _file(name, directory, ext);
      try {
        if (await file.exists()) await file.delete();
      } catch (e) {
        debugPrint('[BoxRecovery] $name: could not remove $ext: $e');
      }
    }
  }

  /// Hive lowercases a box name to build its filename.
  static File _file(String name, String directory, String ext) =>
      File('$directory${Platform.pathSeparator}${name.toLowerCase()}$ext');

  static Future<void> _close(String name) async {
    if (!Hive.isBoxOpen(name)) return;
    try {
      await Hive.box(name).close();
    } catch (_) {}
  }
}
