import 'dart:collection';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

enum LogLevel { info, warn, error }

class LogLine {
  final DateTime time;
  final LogLevel level;
  final String message;
  const LogLine(this.time, this.level, this.message);
}

class PlayerLog {
  PlayerLog._();
  static final PlayerLog instance = PlayerLog._();

  static const int _maxLines = 800;
  final Queue<LogLine> _lines = Queue<LogLine>();

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  final Map<String, String> _context = <String, String>{};

  String _appVersion = '';
  String _device = '';

  List<LogLine> get lines => List.unmodifiable(_lines);

  Future<void> init() async {
    if (_appVersion.isNotEmpty) return;
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      _appVersion = 'unknown';
    }
    try {
      _device =
          '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {
      _device = 'unknown';
    }
  }

  void setContext(Map<String, String?> values) {
    values.forEach((k, v) {
      if (v == null || v.isEmpty) {
        _context.remove(k);
      } else {
        _context[k] = redact(v);
      }
    });
    _bump();
  }

  void clearContext() {
    _context.clear();
    _bump();
  }

  void add(String message, {LogLevel level = LogLevel.info}) {
    message = redact(message);
    if (kDebugMode) {
      final prefix = switch (level) {
        LogLevel.error => '[PLAYER] ✗',
        LogLevel.warn => '[PLAYER] ⚠',
        LogLevel.info => '[PLAYER]',
      };
      debugPrint('$prefix $message');
    }
    _lines.add(LogLine(DateTime.now(), level, message));
    while (_lines.length > _maxLines) {
      _lines.removeFirst();
    }
    _bump();
  }

  /// Header lines whose values are credentials rather than diagnostics.
  static final RegExp _secretHeader = RegExp(
    r'^(\s*)(cookie|set-cookie|authorization|proxy-authorization|x-auth-token|x-api-key)(\s*[:=]\s*).+$',
    caseSensitive: false,
    multiLine: true,
  );

  /// Query parameters that carry a session, a signature or a key.
  static final RegExp _secretParam = RegExp(
    r'([?&](?:token|access_token|refresh_token|auth|key|api_key|apikey|sig|signature|jwt|session|sessionid|sid|cf_clearance|password|pass|secret)=)[^&\s#"]+',
    caseSensitive: false,
  );

  static final RegExp _bearer = RegExp(r'(Bearer\s+)[A-Za-z0-9\-._~+/]+=*');

  /// Strips credentials out of a line before it is kept.
  ///
  /// The log is shareable by design — the viewer's Share and Copy buttons
  /// exist so a user can paste it into a bug report — and the player writes
  /// every request header and the full stream URL into it. Those carry the
  /// provider's cookies (including `cf_clearance`), signed-URL tokens and,
  /// through the backend, bearer tokens. What a report needs is that a header
  /// or parameter was there, not its value, so the value is replaced here,
  /// once, rather than at each of the call sites that log.
  static String redact(String input) {
    if (input.isEmpty) return input;
    return input
        .replaceAllMapped(
          _secretHeader,
          (m) => '${m[1]}${m[2]}${m[3]}<redacted>',
        )
        .replaceAllMapped(_secretParam, (m) => '${m[1]}<redacted>')
        .replaceAllMapped(_bearer, (m) => '${m[1]}<redacted>');
  }

  void i(String message) => add(message);
  void w(String message) => add(message, level: LogLevel.warn);
  void e(String message) => add(message, level: LogLevel.error);

  void clear() {
    _lines.clear();
    _bump();
  }

  void _bump() => revision.value++;

  String _two(int n) => n.toString().padLeft(2, '0');
  String _three(int n) => n.toString().padLeft(3, '0');

  String stamp(DateTime t) =>
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}.${_three(t.millisecond)}';

  String formatForShare() {
    final b = StringBuffer()
      ..writeln('Soplay player logs')
      ..writeln('app: ${_appVersion.isEmpty ? 'unknown' : _appVersion}')
      ..writeln('device: ${_device.isEmpty ? 'unknown' : _device}')
      ..writeln('captured: ${DateTime.now().toIso8601String()}');
    if (_context.isNotEmpty) {
      b.writeln('--- context ---');
      _context.forEach((k, v) => b.writeln('$k: $v'));
    }
    b.writeln('--- log (${_lines.length}) ---');
    for (final l in _lines) {
      final tag = switch (l.level) {
        LogLevel.error => 'E',
        LogLevel.warn => 'W',
        LogLevel.info => 'I',
      };
      b.writeln('${stamp(l.time)} $tag  ${l.message}');
    }
    return b.toString();
  }
}
