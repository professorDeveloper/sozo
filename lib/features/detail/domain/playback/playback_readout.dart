import 'package:soplay/features/detail/domain/entities/video_source_entity.dart';
import 'package:soplay/features/detail/domain/playback/player_info_fields.dart';

/// One labelled fact about what is playing.
class PlaybackReadoutRow {
  const PlaybackReadoutRow(this.id, this.labelKey, this.value);

  /// Which switchable field this row is, from [PlayerInfoFields].
  final String id;

  /// Translation key. The value beside it is data, never a sentence, so it is
  /// the same in every language.
  final String labelKey;
  final String value;
}

/// What is actually playing, as rows a viewer or a bug report can read.
///
/// The player could say nothing about itself. When a stream stuttered, or came
/// out the wrong size, or would not decode, the report was "the app is broken"
/// and the only way to learn more was the diagnostics log — a wall of text
/// aimed at whoever wrote the player, not at whoever is watching.
///
/// Everything here is already in hand: the engine's own value object and the
/// source entry the ladder picked. Nothing is measured, fetched or estimated.
///
/// ## What is deliberately absent
///
/// No bitrate and no dropped-frame count. `VideoPlayerValue` exposes neither —
/// its whole surface is duration, position, buffered ranges, size, speed and
/// the buffering flag — and media_kit's fallback does not fill the gap. Showing
/// an invented number in a panel people will screenshot into bug reports is
/// worse than showing one fewer row.
///
/// Pure: entities in, rows out. No Flutter, no getIt, no I/O, no clock.
abstract final class PlaybackReadout {
  /// The rows to render, in reading order. Anything unknown is left out rather
  /// than shown as a dash — a short panel beats a padded one.
  static List<PlaybackReadoutRow> rows({
    required int videoWidth,
    required int videoHeight,
    required Duration position,
    required Duration duration,
    required Duration bufferedTo,
    required double playbackSpeed,
    required bool isLive,
    required bool isBuffering,
    required String engineId,
    required String providerId,
    String? serverLabel,
    String? mediaType,
    VideoSourceEntity? source,
    String? streamUrl,
    Set<String>? fields,
  }) {
    final out = <PlaybackReadoutRow>[];
    // Null means "whatever the viewer has not chosen against" — the shipped
    // set. An EMPTY set is a real answer (every row switched off) and must not
    // be confused with it, which `??` alone would do.
    final enabled = fields ?? PlayerInfoFields.defaults;

    void add(String id, String? value) {
      if (value == null || value.isEmpty) return;
      if (!enabled.contains(id)) return;
      final field = PlayerInfoFields.byId(id);
      if (field == null) return;
      out.add(PlaybackReadoutRow(id, field.labelKey, value));
    }

    add('resolution', resolution(videoWidth, videoHeight));
    add('engine', engineId);
    add('provider', providerId);
    add('server', serverLabel);
    add('quality', source?.quality);

    // The three that decide whether a device can play a file at all, and the
    // three most worth having in a screenshot when it cannot.
    add('codec', source?.codec);
    add('hdr', source?.hdr);
    if (source?.atmos ?? false) add('audio', 'Atmos');

    add('container', containerOf(mediaType, source?.type));
    add('size', formatBytes(source?.sizeBytes));
    add('host', hostOf(streamUrl));

    if (isLive) {
      add('position', formatClock(position));
    } else {
      add('position', '${formatClock(position)} / ${formatClock(duration)}');
      add('buffer', bufferAhead(position, bufferedTo));
    }
    if (playbackSpeed != 1.0) {
      add('speed', '${trimZeros(playbackSpeed)}×');
    }
    if (isBuffering) add('state', 'buffering');

    return out;
  }

  /// `1920×1080` plus the name people actually use for it, when there is one.
  static String? resolution(int width, int height) {
    if (width <= 0 || height <= 0) return null;
    final name = switch (height) {
      >= 2000 => '4K',
      >= 1400 => '1440p',
      >= 1000 => '1080p',
      >= 700 => '720p',
      >= 460 => '480p',
      _ => null,
    };
    return name == null ? '$width×$height' : '$width×$height · $name';
  }

  /// How far ahead of the playhead the buffer reaches, in whole seconds.
  ///
  /// This is the number that explains a stutter, so it is the one row worth
  /// watching change.
  static String? bufferAhead(Duration position, Duration bufferedTo) {
    final ahead = bufferedTo - position;
    if (ahead.isNegative) return '0s';
    return '${ahead.inSeconds}s';
  }

  /// The stream's container, preferring what the source declared over what the
  /// player was told, since the source is closer to the file.
  static String? containerOf(String? mediaType, String? sourceType) {
    final t = (sourceType?.isNotEmpty ?? false) ? sourceType : mediaType;
    if (t == null || t.isEmpty) return null;
    return switch (t.toLowerCase()) {
      'hls' || 'm3u8' => 'HLS',
      'dash' || 'mpd' => 'DASH',
      'mp4' || 'video' => 'MP4',
      'live' => 'Live',
      _ => t,
    };
  }

  /// The host serving the stream — the single most useful line in a report
  /// about a mirror that has died. Never the full url: it carries tokens.
  static String? hostOf(String? url) {
    if (url == null || url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    final host = uri?.host;
    return (host == null || host.isEmpty) ? null : host;
  }

  static String formatClock(Duration d) {
    final total = d.inSeconds < 0 ? 0 : d.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  static String? formatBytes(int? bytes) {
    if (bytes == null || bytes <= 0) return null;
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final text = value >= 10 || unit == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$text ${units[unit]}';
  }

  static String trimZeros(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}
