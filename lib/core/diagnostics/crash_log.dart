import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'player_log.dart';

/// Uncaught errors, written to a few size-capped files under app support.
///
/// Off Android only: Android reports through Crashlytics. Nothing here leaves
/// the device unless the viewer attaches it to a support ticket.
class CrashLog {
  CrashLog(this.dir, {this.maxBytes = 128 * 1024, this.maxFiles = 3});

  final Directory dir;

  /// Size at which the current file is rotated out.
  final int maxBytes;

  /// Files kept in total, current one included.
  final int maxFiles;

  static CrashLog? instance;

  File _file(int i) => File(
    '${dir.path}${Platform.pathSeparator}crash${i == 0 ? '' : '.$i'}.log',
  );

  /// Newest first: `crash.log`, `crash.1.log`, ...
  List<File> get files => [
    for (var i = 0; i < maxFiles; i++)
      if (_file(i).existsSync()) _file(i),
  ];

  /// Synchronous on purpose: the process may be about to die.
  void record(Object error, StackTrace? stack, {String? source}) {
    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final entry = StringBuffer()
        ..writeln(
          '--- ${DateTime.now().toIso8601String()}'
          '${source == null ? '' : ' [$source]'}',
        )
        ..writeln(PlayerLog.redact('$error'));
      if (stack != null) entry.writeln(PlayerLog.redact('$stack'));
      final text = entry.toString();
      final current = _file(0);
      final size = current.existsSync() ? current.lengthSync() : 0;
      if (size > 0 && size + text.length > maxBytes) _rotate();
      _file(0).writeAsStringSync(
        text.length > maxBytes ? text.substring(0, maxBytes) : text,
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // A crash log that crashes helps nobody.
    }
  }

  void _rotate() {
    final oldest = _file(maxFiles - 1);
    if (oldest.existsSync()) oldest.deleteSync();
    for (var i = maxFiles - 2; i >= 0; i--) {
      final f = _file(i);
      if (f.existsSync()) f.renameSync(_file(i + 1).path);
    }
  }

  /// Everything kept, oldest first, cut to the newest [maxChars].
  String read({int? maxChars}) {
    final buf = StringBuffer();
    for (final f in files.reversed) {
      try {
        buf.write(f.readAsStringSync());
      } catch (_) {}
    }
    final all = buf.toString();
    if (maxChars == null || all.length <= maxChars) return all;
    return all.substring(all.length - maxChars);
  }

  void clear() {
    for (final f in files) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
  }

  /// Routes Flutter's and the platform dispatcher's uncaught errors here.
  static Future<void> install() async {
    if (kIsWeb || Platform.isAndroid) return;
    try {
      final support = await getApplicationSupportDirectory();
      instance = CrashLog(
        Directory('${support.path}${Platform.pathSeparator}crash_logs'),
      );
    } catch (_) {
      return;
    }
    final log = instance!;
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      log.record(details.exception, details.stack, source: 'flutter');
      if (previous != null) {
        previous(details);
      } else {
        FlutterError.presentError(details);
      }
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      if (kDebugMode) debugPrint('[uncaught] $error\n$stack');
      log.record(error, stack, source: 'platform');
      return true;
    };
  }
}
