import 'package:soplay/features/torrent/domain/entities/release_info.dart';

/// Turns an anime release file name into a [ReleaseInfo].
///
/// Trackers give us almost no structured metadata — Nyaa's RSS has seeders,
/// size and a category, and nothing about resolution, codec or audio. The file
/// name is the only place that information exists before the torrent is added,
/// so every quality filter in the torrent search depends on this parser.
///
/// It is intentionally forgiving. Groups disagree about separators, ordering
/// and capitalisation, and roughly a third of names in the wild are missing
/// half the fields. A partially filled [ReleaseInfo] is a useful result; a
/// thrown exception in the middle of a result list is not. Nothing in here
/// throws.
///
/// Two naming families are handled, both documented at
/// <https://wotaku.wiki/torrenting/nyaa>:
///
///   `[SubsPlease] Sousou no Frieren S2 - 01 (1080p) [4277EF46].mkv`
///   `Frieren.S02E01.1080p.CR.WEB-DL.AAC2.0.H.264-VARYG.mkv`
abstract final class ReleaseNameParser {
  /// Bracketed group at the start: `[SubsPlease] ...`.
  static final _leadingGroup = RegExp(r'^\s*[\[\(]([^\]\)]{1,40})[\]\)]');

  /// Scene-style trailing group: `...-VARYG.mkv`, `...-EMBER`.
  static final _trailingGroup =
      RegExp(r'-([A-Za-z0-9]{2,20})(?:\.(?:mkv|mp4|avi))?\s*$');

  /// `1080p`, `2160p`, and the `1920x1080` form older BD rips use.
  static final _resolutionP = RegExp(r'(?<![\d])(\d{3,4})[pi]\b', caseSensitive: false);
  static final _resolutionXY = RegExp(r'\b(\d{3,4})\s*[x×]\s*(\d{3,4})\b');

  /// CRC32 checksum: exactly 8 hex digits in brackets.
  static final _crc32 = RegExp(r'[\[\(]([0-9A-Fa-f]{8})[\]\)]');

  static final _container = RegExp(r'\.(mkv|mp4|avi|webm)\s*$', caseSensitive: false);

  static final _bitDepth = RegExp(r'\b(8|10|12)\s*-?\s*bits?\b', caseSensitive: false);
  static final _hi10p = RegExp(r'\bHi10P?\b', caseSensitive: false);

  /// `S02E01`, `S2 - 01`, ` - 08 `, and ranges like `01-12` / `01~12`.
  static final _seasonEpisode =
      RegExp(r'\bS(\d{1,2})\s*E(\d{1,3})\b', caseSensitive: false);
  static final _seasonOnly = RegExp(r'\bS(?:eason\s*)?(\d{1,2})\b', caseSensitive: false);
  static final _episodeRange =
      RegExp(r'(?:^|[\s\-_.])(\d{1,3})\s*[-~]\s*(\d{1,3})(?:[\s\[\(]|$)');
  static final _episodeDash = RegExp(r'\s-\s(\d{1,3})(?:v\d)?(?:\s|$|\[|\()');

  static const _batchWords = [
    'batch',
    'season pack',
    'complete',
    'seasons',
    'movies',
    'collection',
    'bd box',
  ];

  /// Parses [name]. Never throws; returns an empty [ReleaseInfo] in the worst
  /// case.
  static ReleaseInfo parse(String name) {
    try {
      return _parse(name);
    } catch (_) {
      return const ReleaseInfo();
    }
  }

  static ReleaseInfo _parse(String raw) {
    final name = raw.trim();
    final lower = name.toLowerCase();

    final group = _parseGroup(name);
    final container = _container.firstMatch(name)?.group(1)?.toLowerCase();
    final crc32 = _crc32.firstMatch(name)?.group(1)?.toUpperCase();

    final episodes = _parseEpisodes(name);
    final batch = episodes.end != null ||
        _batchWords.any(lower.contains) ||
        // A category-less multi-episode hint: "S1+S2", "1-24".
        RegExp(r'\bS\d\s*\+\s*S\d\b', caseSensitive: false).hasMatch(name);

    return ReleaseInfo(
      group: group,
      showTitle: _parseTitle(name, group),
      season: episodes.season,
      episode: episodes.start,
      episodeEnd: episodes.end,
      resolutionHeight: _parseResolution(name),
      source: _parseSource(lower),
      codec: _parseCodec(lower),
      audio: _parseAudio(lower),
      bitDepth: _parseBitDepth(name),
      crc32: crc32,
      container: container,
      subtitles: _parseSubtitles(lower, container),
      dualAudio: lower.contains('dual audio') ||
          lower.contains('dual-audio') ||
          lower.contains('dualaudio'),
      multiSubtitle: lower.contains('multi-sub') ||
          lower.contains('multisub') ||
          lower.contains('multi sub'),
      multiAudio: lower.contains('multi-audio') ||
          lower.contains('multiaudio') ||
          lower.contains('multi-dub') ||
          lower.contains('multi audio'),
      hdr: RegExp(r'\bHDR(?:10)?(?:\+)?\b', caseSensitive: false).hasMatch(name) ||
          lower.contains('dolby vision') ||
          RegExp(r'\bDV\b').hasMatch(name),
      batch: batch,
      uncensored: lower.contains('uncensored') || lower.contains('uncut'),
    );
  }

  static String? _parseGroup(String name) {
    final leading = _leadingGroup.firstMatch(name)?.group(1)?.trim();
    // A leading bracket holding only a date or a CRC is metadata, not a group:
    // `[250209][Artist] Title` is common on Sukebei.
    if (leading != null &&
        leading.isNotEmpty &&
        !RegExp(r'^[0-9A-Fa-f]{8}$').hasMatch(leading) &&
        !RegExp(r'^\d{6,8}$').hasMatch(leading)) {
      return leading;
    }
    final trailing = _trailingGroup.firstMatch(name)?.group(1);
    // Guard against swallowing a resolution or codec: `...-1080p`, `...-x264`.
    if (trailing != null &&
        !RegExp(r'^\d+[pi]?$').hasMatch(trailing) &&
        !RegExp(r'^(x|h)26[45]$', caseSensitive: false).hasMatch(trailing)) {
      return trailing;
    }
    return null;
  }

  /// Strips the group, every bracketed tag group, the extension and any
  /// trailing episode marker, leaving something close to the show's name.
  static String? _parseTitle(String name, String? group) {
    var out = name;
    if (group != null) {
      out = out
          .replaceFirst(RegExp(r'^\s*[\[\(]' + RegExp.escape(group) + r'[\]\)]\s*'), '')
          .replaceFirst(RegExp(r'-' + RegExp.escape(group) + r'\s*$'), '');
    }
    out = out
        .replaceAll(_container, '')
        .replaceAll(RegExp(r'[\[\(][^\]\)]*[\]\)]'), ' ')
        .replaceAll(RegExp(r'\s*-\s*\d{1,3}(v\d)?\s*$'), ' ')
        .replaceAll(RegExp(r'\bS\d{1,2}E\d{1,3}\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'[._]+'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim()
        .replaceAll(RegExp(r'^[-–—\s]+|[-–—\s]+$'), '');
    return out.isEmpty ? null : out;
  }

  static ({int? season, int? start, int? end}) _parseEpisodes(String name) {
    final se = _seasonEpisode.firstMatch(name);
    if (se != null) {
      return (
        season: int.tryParse(se.group(1)!),
        start: int.tryParse(se.group(2)!),
        end: null,
      );
    }

    final season = int.tryParse(_seasonOnly.firstMatch(name)?.group(1) ?? '');

    // Ranges are checked before single episodes: `01-12` must not be read as
    // episode 1.
    final range = _episodeRange.firstMatch(name);
    if (range != null) {
      final start = int.tryParse(range.group(1)!);
      final end = int.tryParse(range.group(2)!);
      if (start != null && end != null && end > start) {
        return (season: season, start: start, end: end);
      }
    }

    final single = _episodeDash.firstMatch(name);
    return (
      season: season,
      start: int.tryParse(single?.group(1) ?? ''),
      end: null,
    );
  }

  static int? _parseResolution(String name) {
    final xy = _resolutionXY.firstMatch(name);
    if (xy != null) {
      // `1920x1032` — the height is the second number, and cropped heights
      // like 1032 are normal for scope-ratio films. Snap to the nearest tier
      // so filters still group them with 1080p.
      final h = int.tryParse(xy.group(2)!);
      if (h != null) return _snapResolution(h);
    }

    for (final m in _resolutionP.allMatches(name)) {
      final value = int.tryParse(m.group(1)!);
      if (value == null) continue;
      // 480p/720p/1080p/1440p/2160p are the only plausible values; anything
      // else in that shape is a bitrate or an episode number.
      if (value >= 240 && value <= 4320) return value;
    }

    final lower = name.toLowerCase();
    if (lower.contains('2160') || lower.contains('4k') || lower.contains('uhd')) {
      return 2160;
    }
    return null;
  }

  static int _snapResolution(int height) {
    const tiers = [480, 576, 720, 1080, 1440, 2160, 4320];
    var best = tiers.first;
    for (final t in tiers) {
      if ((height - t).abs() < (height - best).abs()) best = t;
    }
    // Only snap when it is genuinely close — a real 900p encode stays 900p.
    return (height - best).abs() <= 60 ? best : height;
  }

  static ReleaseSource? _parseSource(String lower) {
    // Order matters: "BD Remux" must resolve to remux, and "WEB-DLRip" to a
    // rip. Most specific first.
    if (lower.contains('remux')) return ReleaseSource.remux;
    if (lower.contains('mini-encode') ||
        lower.contains('miniencode') ||
        lower.contains('mini encode')) {
      return ReleaseSource.miniEncode;
    }
    if (lower.contains('re-encode') || lower.contains('reencode')) {
      return ReleaseSource.reEncode;
    }
    if (lower.contains('bdiso') ||
        lower.contains('bdmv') ||
        lower.contains('bd box') ||
        lower.contains('iso')) {
      return ReleaseSource.bluRayDisc;
    }
    if (lower.contains('web-dl') || lower.contains('webdl') || lower.contains('web dl')) {
      return ReleaseSource.webDl;
    }
    if (lower.contains('webrip') || lower.contains('web-rip') || lower.contains('web rip')) {
      return ReleaseSource.webRip;
    }
    if (lower.contains('bdrip') ||
        lower.contains('bd-rip') ||
        lower.contains('bluray') ||
        lower.contains('blu-ray') ||
        RegExp(r'\bbd\b').hasMatch(lower)) {
      return ReleaseSource.bluRayEncode;
    }
    if (lower.contains('hdtv') || lower.contains('tvrip')) return ReleaseSource.hdtv;
    if (lower.contains('dvdrip') || RegExp(r'\bdvd\b').hasMatch(lower)) {
      return ReleaseSource.dvd;
    }
    // A bare "WEB" is almost always a WEB-DL from a streaming service.
    if (RegExp(r'\bweb\b').hasMatch(lower)) return ReleaseSource.webDl;
    return null;
  }

  static VideoCodec? _parseCodec(String lower) {
    if (RegExp(r'\b(x|h)\s*\.?\s*265\b').hasMatch(lower) || lower.contains('hevc')) {
      return VideoCodec.h265;
    }
    if (RegExp(r'\b(x|h)\s*\.?\s*264\b').hasMatch(lower) || lower.contains('avc')) {
      return VideoCodec.h264;
    }
    if (RegExp(r'\bav1\b').hasMatch(lower)) return VideoCodec.av1;
    if (RegExp(r'\bvp9\b').hasMatch(lower)) return VideoCodec.vp9;
    return null;
  }

  static Set<AudioFormat> _parseAudio(String lower) {
    final out = <AudioFormat>{};
    if (_audio(lower, 'flac')) out.add(AudioFormat.flac);
    // EAC3 is checked first: the string "EAC3" contains "AC3", and DD+ / DDP
    // are the same codec under Dolby's marketing names.
    if (_audio(lower, 'eac-?3') ||
        _audio(lower, 'e-ac-3') ||
        lower.contains('ddp') ||
        lower.contains('dd+')) {
      out.add(AudioFormat.eac3);
    } else if (_audio(lower, 'ac-?3') || _audio(lower, 'dd')) {
      out.add(AudioFormat.ac3);
    }
    if (_audio(lower, 'aac')) out.add(AudioFormat.aac);
    if (_audio(lower, 'opus')) out.add(AudioFormat.opus);
    if (_audio(lower, 'mp3')) out.add(AudioFormat.mp3);
    if (_audio(lower, 'dts(?:-hd)?')) out.add(AudioFormat.dts);
    return out;
  }

  /// Matches an audio codec name that may be followed immediately by a channel
  /// count, which a plain `\b` boundary would reject.
  ///
  /// Groups write the layout straight onto the codec — `AAC2.0`, `EAC3 5.1`,
  /// `DDP5.1`, `FLAC2.0`. Anchoring on "not followed by another letter" instead
  /// of a word boundary keeps those while still refusing `aacs` or `ddl`.
  static bool _audio(String lower, String pattern) =>
      RegExp('(?<![a-z0-9])$pattern(?![a-z])').hasMatch(lower);

  static int? _parseBitDepth(String name) {
    if (_hi10p.hasMatch(name)) return 10;
    final m = _bitDepth.firstMatch(name);
    final value = int.tryParse(m?.group(1) ?? '');
    // "8bit"/"10bit" only; a stray "12bit" is real but rare, and anything else
    // matched here would be a false positive.
    return value == 8 || value == 10 || value == 12 ? value : null;
  }

  static SubtitleKind? _parseSubtitles(String lower, String? container) {
    if (lower.contains('sdh')) return SubtitleKind.sdh;
    if (lower.contains('hardsub') ||
        lower.contains('hard-sub') ||
        lower.contains('hardcoded')) {
      return SubtitleKind.openCaptions;
    }
    if (lower.contains('softsub') ||
        lower.contains('soft-sub') ||
        lower.contains('multi-sub') ||
        lower.contains('multisub')) {
      return SubtitleKind.closedCaptions;
    }
    // MP4 cannot carry the ASS/SSA tracks fansubs use, so an MP4 anime release
    // is hardsubbed in practice. MKV says nothing either way.
    if (container == 'mp4') return SubtitleKind.openCaptions;
    return null;
  }
}
