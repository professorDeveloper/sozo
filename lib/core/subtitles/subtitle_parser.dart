import 'dart:convert';
import 'dart:io';

import 'package:video_player/video_player.dart';

/// Why a subtitle file could not be turned into cues. The player maps each of
/// these onto its own message — the old code swallowed every failure and still
/// toasted "Subtitle loaded".
enum SubtitleParseFailure {
  /// Download succeeded but the body was empty (or whitespace only).
  empty,

  /// A .zip / .rar container. We cannot unpack these without a new dependency.
  archive,

  /// An HTML page served with status 200 — usually a captcha or an error page.
  html,

  /// Recognisable as a subtitle container we do not support.
  unsupportedFormat,

  /// The format was understood but the parser produced zero cues.
  noCues,
}

/// Either a non-empty, start-sorted list of cues or a [SubtitleParseFailure].
class SubtitleParseResult {
  const SubtitleParseResult.success(this.captions) : failure = null;
  const SubtitleParseResult.failed(SubtitleParseFailure this.failure)
    : captions = const [];

  final List<Caption> captions;
  final SubtitleParseFailure? failure;

  bool get isSuccess => failure == null && captions.isNotEmpty;
}

/// Turns the raw bytes of a downloaded subtitle into cues.
///
/// This exists because handing the bytes straight to video_player's
/// [SubRipCaptionFile] loses most real-world files: its block reader `break`s
/// (not `continue`s) on the first malformed block, so a single empty-bodied cue
/// or one stray blank line truncates the whole rest of the file, and its
/// timestamp regex is `\d\d:\d\d:\d\d,\d\d\d` so single-digit hours drop every
/// cue. We sniff the container, decode the text with the right codec, and
/// re-emit canonical SubRip before parsing.
SubtitleParseResult parseSubtitleBytes(
  List<int> bytes, {
  String url = '',
  String declaredFormat = '',
}) {
  if (bytes.isEmpty) {
    return const SubtitleParseResult.failed(SubtitleParseFailure.empty);
  }

  // gzip — transparently unwrap and re-run on the payload.
  if (bytes.length > 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
    try {
      return parseSubtitleBytes(
        gzip.decode(bytes),
        url: url,
        declaredFormat: declaredFormat,
      );
    } catch (_) {
      return const SubtitleParseResult.failed(SubtitleParseFailure.archive);
    }
  }
  // 'PK' (zip) and 'Rar!' — real containers, not text.
  if (bytes.length > 4 &&
      ((bytes[0] == 0x50 && bytes[1] == 0x4B) ||
          (bytes[0] == 0x52 &&
              bytes[1] == 0x61 &&
              bytes[2] == 0x72 &&
              bytes[3] == 0x21))) {
    return const SubtitleParseResult.failed(SubtitleParseFailure.archive);
  }

  final text = decodeSubtitleBytes(bytes);
  return parseSubtitleText(text, url: url, declaredFormat: declaredFormat);
}

/// Same as [parseSubtitleBytes] once the bytes are already text.
SubtitleParseResult parseSubtitleText(
  String raw, {
  String url = '',
  String declaredFormat = '',
}) {
  final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final trimmed = text.trimLeft();
  if (trimmed.isEmpty) {
    return const SubtitleParseResult.failed(SubtitleParseFailure.empty);
  }

  final head = trimmed.length > 600 ? trimmed.substring(0, 600) : trimmed;
  final lowerHead = head.toLowerCase();
  if (lowerHead.startsWith('<!doctype html') ||
      lowerHead.startsWith('<html') ||
      (trimmed.startsWith('<') && lowerHead.contains('<body'))) {
    return const SubtitleParseResult.failed(SubtitleParseFailure.html);
  }

  final format = declaredFormat.trim().toUpperCase();
  final isVtt =
      trimmed.startsWith('WEBVTT') ||
      (format == 'VTT' && !lowerHead.contains('dialogue:'));
  final isAss =
      lowerHead.contains('[script info]') ||
      lowerHead.contains('[events]') ||
      lowerHead.contains('dialogue:') ||
      format == 'ASS' ||
      format == 'SSA';

  List<Caption> captions;
  if (isVtt) {
    captions = _sanitize(WebVTTCaptionFile(text).captions);
  } else if (isAss) {
    captions = _sanitize(_parseAss(text));
  } else if (text.contains('-->') ||
      format == 'SRT' ||
      url.toLowerCase().endsWith('.srt')) {
    captions = _sanitize(SubRipCaptionFile(_normalizeSubRip(text)).captions);
  } else if (url.toLowerCase().endsWith('.vtt')) {
    captions = _sanitize(WebVTTCaptionFile(text).captions);
  } else {
    return const SubtitleParseResult.failed(
      SubtitleParseFailure.unsupportedFormat,
    );
  }

  if (captions.isEmpty) {
    return const SubtitleParseResult.failed(SubtitleParseFailure.noCues);
  }
  return SubtitleParseResult.success(captions);
}

/// Drops junk cues and sorts by start time. Nothing in the pipeline sorted
/// before, and the overlay's lookup depends on the order.
List<Caption> _sanitize(List<Caption> input) {
  final out = <Caption>[];
  for (final c in input) {
    if (c.text.trim().isEmpty) continue;
    if (c.end <= c.start) continue;
    out.add(c);
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

// --- SubRip normalisation ---------------------------------------------------

/// Tolerant timing line: optional hours, `,` or `.` as the decimal separator,
/// any amount of whitespace around the arrow, and anything trailing (legacy
/// `X1:100 X2:600 Y1:20 Y2:50` coordinates) simply ignored.
final RegExp _srtTiming = RegExp(
  r'(?:(\d{1,3}):)?(\d{1,2}):(\d{1,2})[,.](\d{1,3})'
  r'\s*-+>\s*'
  r'(?:(\d{1,3}):)?(\d{1,2}):(\d{1,2})[,.](\d{1,3})',
);

final RegExp _onlyDigits = RegExp(r'^\d+$');

/// Rewrites an arbitrary SubRip body into the exact shape video_player's parser
/// accepts: sequential numbering, `HH:MM:SS,mmm --> HH:MM:SS,mmm` timings, a
/// non-empty body, and exactly one blank line between cues.
String _normalizeSubRip(String text) {
  final lines = const LineSplitter().convert(text);

  // Anchor on the timing lines rather than on blank-line separation — blank
  // lines are exactly what the upstream parser mishandles.
  final timingAt = <int>[];
  for (var i = 0; i < lines.length; i++) {
    if (_srtTiming.hasMatch(lines[i])) timingAt.add(i);
  }
  if (timingAt.isEmpty) return '';

  final buf = StringBuffer();
  var number = 0;
  for (var t = 0; t < timingAt.length; t++) {
    final idx = timingAt[t];
    final m = _srtTiming.firstMatch(lines[idx])!;
    final start = _srtStamp(m, 1);
    final end = _srtStamp(m, 5);
    if (end <= start) continue;

    // Body runs to the next timing line, minus that cue's index line and any
    // trailing blanks.
    var stop = t + 1 < timingAt.length ? timingAt[t + 1] : lines.length;
    if (t + 1 < timingAt.length &&
        stop - 1 > idx &&
        _onlyDigits.hasMatch(lines[stop - 1].trim())) {
      stop -= 1;
    }
    final body = <String>[];
    for (var i = idx + 1; i < stop; i++) {
      final line = _stripSubRipMarkup(lines[i]).trimRight();
      if (line.trim().isEmpty) continue;
      body.add(line);
    }
    if (body.isEmpty) continue;

    number += 1;
    buf
      ..writeln(number)
      ..writeln('${_fmtStamp(start)} --> ${_fmtStamp(end)}')
      ..writeln(body.join('\n'))
      ..writeln();
  }
  return buf.toString();
}

final RegExp _htmlTag = RegExp(r'</?[a-zA-Z][^>]*>');

/// SubRip's inline markup — `<i>`, `<b>`, `<font color=…>` — and the ASS
/// position codes fansub SRTs carry (`{\an8}`), none of which the overlay
/// draws. They were shown as typed. WebVTT goes through an HTML parser
/// upstream; SubRip did not.
String _stripSubRipMarkup(String line) => line
    .replaceAll(_htmlTag, '')
    .replaceAll(_assOverride, '')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&');

Duration _srtStamp(RegExpMatch m, int group) {
  final ms = m.group(group + 3)!;
  return Duration(
    hours: int.parse(m.group(group) ?? '0'),
    minutes: int.parse(m.group(group + 1)!),
    seconds: int.parse(m.group(group + 2)!),
    // '5' means 500ms, '05' means 50ms — pad right, not left.
    milliseconds: int.parse(ms.padRight(3, '0')),
  );
}

String _fmtStamp(Duration d) {
  final h = d.inHours.clamp(0, 99).toString().padLeft(2, '0');
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final ms = d.inMilliseconds.remainder(1000).toString().padLeft(3, '0');
  return '$h:$m:$s,$ms';
}

// --- ASS / SSA --------------------------------------------------------------

final RegExp _assOverride = RegExp(r'\{[^}]*\}');

/// An ASS vector drawing: `{\p1}m 0 0 l 100 0 …{\p0}`. With the braces
/// removed, the path's coordinates were drawn on screen as text.
final RegExp _assDrawing = RegExp(
  r'\{[^}]*\\p[1-9][^}]*\}[^{]*(?:\{[^}]*\\p0[^}]*\})?',
);
final RegExp _assStamp = RegExp(
  r'^(\d{1,3}):(\d{1,2}):(\d{1,2})[.,](\d{1,2})$',
);

/// Converts the `Dialogue:` lines of an ASS/SSA script into cues. Feeding these
/// to the SubRip parser throws a FormatException on the very first line.
List<Caption> _parseAss(String text) {
  final lines = const LineSplitter().convert(text);
  var startField = 1;
  var endField = 2;
  var textField = 9;
  final out = <Caption>[];
  var number = 0;

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.toLowerCase().startsWith('format:') &&
        trimmed.toLowerCase().contains('start')) {
      final fields = trimmed
          .substring(trimmed.indexOf(':') + 1)
          .split(',')
          .map((f) => f.trim().toLowerCase())
          .toList();
      final s = fields.indexOf('start');
      final e = fields.indexOf('end');
      final t = fields.indexOf('text');
      if (s >= 0) startField = s;
      if (e >= 0) endField = e;
      if (t >= 0) textField = t;
      continue;
    }
    if (!trimmed.toLowerCase().startsWith('dialogue:')) continue;

    // `Text` is the last field and may itself contain commas, so split only up
    // to the text column and keep the remainder whole.
    final payload = trimmed.substring(trimmed.indexOf(':') + 1);
    final parts = payload.split(',');
    if (parts.length <= textField ||
        parts.length <= startField ||
        parts.length <= endField) {
      continue;
    }
    final start = _parseAssStamp(parts[startField].trim());
    final end = _parseAssStamp(parts[endField].trim());
    if (start == null || end == null || end <= start) continue;

    final body = parts
        .sublist(textField)
        .join(',')
        .replaceAll(_assDrawing, '')
        .replaceAll(_assOverride, '')
        .replaceAll(r'\N', '\n')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\h', ' ')
        .trim();
    if (body.isEmpty) continue;

    number += 1;
    out.add(Caption(number: number, start: start, end: end, text: body));
  }
  return out;
}

Duration? _parseAssStamp(String value) {
  final m = _assStamp.firstMatch(value);
  if (m == null) return null;
  return Duration(
    hours: int.parse(m.group(1)!),
    minutes: int.parse(m.group(2)!),
    seconds: int.parse(m.group(3)!),
    // ASS uses centiseconds.
    milliseconds: int.parse(m.group(4)!.padRight(2, '0')) * 10,
  );
}

// --- Text decoding ----------------------------------------------------------

/// Decodes subtitle bytes without trusting Dio, which always runs
/// `utf8.decode(bytes, allowMalformed: true)` and therefore turns every
/// cp1251/latin1 file into a wall of U+FFFD while leaving the ASCII timings
/// intact — the cues load, the text is destroyed.
String decodeSubtitleBytes(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return _looksCyrillic(bytes)
        ? _decodeCp1251(bytes)
        : latin1.decode(bytes, allowInvalid: true);
  }
}

/// In cp1251 the Cyrillic alphabet occupies 0xC0-0xFF, so a Russian/Ukrainian
/// file is almost entirely high bytes in that range. Western latin1 text uses
/// high bytes far more sparsely and spreads them across 0xA0-0xFF.
bool _looksCyrillic(List<int> bytes) {
  var high = 0;
  var cyrillic = 0;
  for (final b in bytes) {
    if (b < 0x80) continue;
    high += 1;
    if (b >= 0xC0 || b == 0xA8 || b == 0xB8 || b == 0xB2 || b == 0xB3) {
      cyrillic += 1;
    }
  }
  if (high == 0) return false;
  return cyrillic / high >= 0.6;
}

/// cp1251 0x80-0xBF. 0xC0-0xFF is contiguous (U+0410 + offset) so it is
/// computed instead of tabulated.
const List<int> _cp1251High = <int>[
  0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021, //
  0x20AC, 0x2030, 0x0409, 0x2039, 0x040A, 0x040C, 0x040B, 0x040F,
  0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
  0xFFFD, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F,
  0x00A0, 0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7,
  0x0401, 0x00A9, 0x0404, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x0407,
  0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6, 0x00B7,
  0x0451, 0x2116, 0x0454, 0x00BB, 0x0458, 0x0405, 0x0455, 0x0457,
];

String _decodeCp1251(List<int> bytes) {
  final out = List<int>.filled(bytes.length, 0);
  for (var i = 0; i < bytes.length; i++) {
    final b = bytes[i] & 0xFF;
    if (b < 0x80) {
      out[i] = b;
    } else if (b < 0xC0) {
      out[i] = _cp1251High[b - 0x80];
    } else {
      out[i] = 0x0410 + (b - 0xC0);
    }
  }
  return String.fromCharCodes(out);
}
