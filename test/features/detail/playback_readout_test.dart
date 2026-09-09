import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/entities/video_source_entity.dart';
import 'package:soplay/features/detail/domain/playback/player_info_fields.dart';
import 'package:soplay/features/detail/domain/playback/playback_readout.dart';

VideoSourceEntity src({
  String quality = 'Voe · 1080p',
  String? codec,
  String? hdr,
  bool atmos = false,
  int? sizeBytes,
  String? type,
}) =>
    VideoSourceEntity(
      quality: quality,
      videoUrl: 'https://cdn.test/a.m3u8',
      isDefault: false,
      accessible: true,
      codec: codec,
      hdr: hdr,
      atmos: atmos,
      sizeBytes: sizeBytes,
      type: type,
    );

List<PlaybackReadoutRow> build({
  int width = 1920,
  int height = 1080,
  Duration position = const Duration(minutes: 12),
  Duration duration = const Duration(minutes: 47),
  Duration bufferedTo = const Duration(minutes: 12, seconds: 30),
  double speed = 1.0,
  bool isLive = false,
  bool isBuffering = false,
  String engineId = 'media_kit',
  String providerId = 'anilist',
  String? serverLabel = 'Voe',
  String? mediaType,
  VideoSourceEntity? source,
  String? streamUrl = 'https://cdn.example.test/x/a.m3u8?token=secret',
  // Every field switched on unless a test says otherwise: these exercise what
  // the readout can COMPUTE, which is a separate question from what a viewer
  // has chosen to see. The picker has its own tests for that.
  Set<String>? fields,
}) =>
    PlaybackReadout.rows(
      fields: fields ?? {for (final f in PlayerInfoFields.all) f.id},
      videoWidth: width,
      videoHeight: height,
      position: position,
      duration: duration,
      bufferedTo: bufferedTo,
      playbackSpeed: speed,
      isLive: isLive,
      isBuffering: isBuffering,
      engineId: engineId,
      providerId: providerId,
      serverLabel: serverLabel,
      mediaType: mediaType,
      source: source,
      streamUrl: streamUrl,
    );

String? valueFor(List<PlaybackReadoutRow> rows, String key) {
  for (final r in rows) {
    if (r.labelKey == key) return r.value;
  }
  return null;
}

void main() {
  group('what the panel says', () {
    test('resolution carries both the numbers and the name', () {
      expect(valueFor(build(), 'player.info_resolution'), '1920×1080 · 1080p');
      expect(valueFor(build(width: 3840, height: 2160), 'player.info_resolution'),
          '3840×2160 · 4K');
    });

    test('an odd size still reports its numbers', () {
      // Anamorphic and cropped encodes are common; a missing name must not
      // cost the row.
      expect(valueFor(build(width: 1024, height: 436), 'player.info_resolution'),
          '1024×436');
    });

    test('an uninitialised player reports no resolution at all', () {
      expect(valueFor(build(width: 0, height: 0), 'player.info_resolution'),
          isNull);
    });

    test('buffer ahead is the number that explains a stutter', () {
      expect(valueFor(build(), 'player.info_buffer'), '30s');
    });

    test('a playhead past the buffer reads 0s, never a negative', () {
      final rows = build(
        position: const Duration(minutes: 13),
        bufferedTo: const Duration(minutes: 12),
      );
      expect(valueFor(rows, 'player.info_buffer'), '0s');
    });

    test('live drops duration and buffer, which mean nothing there', () {
      final rows = build(isLive: true);
      expect(valueFor(rows, 'player.info_position'), '12:00');
      expect(valueFor(rows, 'player.info_buffer'), isNull);
    });

    test('the codec trio is surfaced when the source declared it', () {
      final rows = build(
        source: src(codec: 'h265', hdr: 'dv', atmos: true),
      );
      expect(valueFor(rows, 'player.info_codec'), 'h265');
      expect(valueFor(rows, 'player.info_hdr'), 'dv');
      expect(valueFor(rows, 'player.info_audio'), 'Atmos');
    });

    test('rows nobody can fill are omitted, not padded with dashes', () {
      final rows = build(source: null, serverLabel: null);
      expect(valueFor(rows, 'player.info_codec'), isNull);
      expect(valueFor(rows, 'player.info_server'), isNull);
      expect(valueFor(rows, 'player.info_audio'), isNull);
      expect(rows.every((r) => r.value.isNotEmpty), isTrue);
    });

    test('speed only appears when it is not 1x', () {
      expect(valueFor(build(), 'player.info_speed'), isNull);
      expect(valueFor(build(speed: 2.0), 'player.info_speed'), '2×');
      expect(valueFor(build(speed: 1.25), 'player.info_speed'), '1.25×');
    });

    test('buffering is stated while it is happening', () {
      expect(valueFor(build(), 'player.info_state'), isNull);
      expect(valueFor(build(isBuffering: true), 'player.info_state'),
          'buffering');
    });
  });

  group('the host row', () {
    test('is the host alone — never the url, which carries tokens', () {
      // This panel is made to be screenshotted into a bug report.
      final rows = build(
          streamUrl: 'https://cdn.example.test/x/a.m3u8?token=secret');
      expect(valueFor(rows, 'player.info_host'), 'cdn.example.test');
      expect(rows.every((r) => !r.value.contains('secret')), isTrue);
    });

    test('a url that will not parse costs the row, not the panel', () {
      expect(valueFor(build(streamUrl: 'not a url'), 'player.info_host'), isNull);
      expect(valueFor(build(streamUrl: ''), 'player.info_host'), isNull);
    });
  });

  group('container', () {
    test('the source wins over what the player was told', () {
      final rows = build(mediaType: 'video', source: src(type: 'hls'));
      expect(valueFor(rows, 'player.info_container'), 'HLS');
    });

    test('falls back to the media type when the source is silent', () {
      expect(valueFor(build(mediaType: 'mp4'), 'player.info_container'), 'MP4');
    });

    test('an unknown container is shown verbatim rather than dropped', () {
      expect(valueFor(build(mediaType: 'mkv'), 'player.info_container'), 'mkv');
    });
  });

  group('helpers', () {
    test('the clock drops the hour until there is one', () {
      expect(PlaybackReadout.formatClock(const Duration(seconds: 65)), '01:05');
      expect(PlaybackReadout.formatClock(const Duration(hours: 2, minutes: 3)),
          '2:03:00');
      expect(PlaybackReadout.formatClock(const Duration(seconds: -5)), '00:00');
    });

    test('bytes scale readably and an unstated size is absent', () {
      expect(PlaybackReadout.formatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
      expect(PlaybackReadout.formatBytes(17179869184), '16 GB');
      expect(PlaybackReadout.formatBytes(null), isNull);
      expect(PlaybackReadout.formatBytes(0), isNull);
    });
  });

  test('every row has a player.info_* key the locales must define', () {
    final rows = build(source: src(codec: 'h264', sizeBytes: 1 << 30));
    expect(rows, isNotEmpty);
    for (final r in rows) {
      expect(r.labelKey, startsWith('player.info_'));
    }
    for (final locale in const ['en', 'uz', 'ru', 'ar']) {
      final text = File('assets/translations/$locale.json').readAsStringSync();
      for (final r in rows) {
        final leaf = r.labelKey.split('.').last;
        expect(text.contains('"$leaf"'), isTrue,
            reason: '$locale.json is missing ${r.labelKey}');
      }
    }
  });

  test('the domain layer stays free of Flutter', () {
    final source = File(
      'lib/features/detail/domain/playback/playback_readout.dart',
    ).readAsStringSync();
    expect(source.contains('package:flutter/'), isFalse);
    expect(source.contains('easy_localization'), isFalse);
  });
}
