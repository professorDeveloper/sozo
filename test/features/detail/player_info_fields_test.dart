import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/playback/player_info_fields.dart';
import 'package:soplay/features/detail/domain/playback/playback_readout.dart';

void main() {
  group('what ships', () {
    test('is a handful, not the whole list', () {
      // Fifteen rows over the picture is furniture. The ones on by default are
      // the ones that answer a complaint.
      expect(PlayerInfoFields.defaults.length,
          lessThan(PlayerInfoFields.all.length));
      expect(PlayerInfoFields.defaults, isNotEmpty);
    });

    test('and includes the rows that explain a stutter or a bad picture', () {
      expect(
        PlayerInfoFields.defaults,
        containsAll(<String>['resolution', 'buffer', 'quality', 'host']),
      );
    });

    test('ids are unique — two fields cannot share a stored key', () {
      final ids = PlayerInfoFields.all.map((f) => f.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every field names a translation key', () {
      for (final f in PlayerInfoFields.all) {
        expect(f.labelKey, startsWith('player.info_'), reason: f.id);
      }
    });
  });

  group('storage', () {
    test('nothing stored is the shipped set, not an empty panel', () {
      expect(PlayerInfoFields.fromStored(null), PlayerInfoFields.defaults);
      expect(PlayerInfoFields.fromStored(const {}), PlayerInfoFields.defaults);
    });

    test('an explicit "off" survives a reload', () {
      final stored = PlayerInfoFields.toStored({'resolution'});
      final back = PlayerInfoFields.fromStored(stored);
      expect(back, {'resolution'});
      expect(back, isNot(contains('buffer')),
          reason: 'on by default, but explicitly turned off');
    });

    test('a field added since the choices were saved takes its own default',
        () {
      // The reason storage is explicit answers rather than a list of enabled
      // ids: with a list, "absent" would mean both "turned off" and "did not
      // exist yet", so every new row would arrive off for everyone who had
      // ever opened the screen, with nothing on screen to explain it.
      final stored = PlayerInfoFields.toStored(PlayerInfoFields.defaults)
        ..remove('resolution')
        ..remove('engine');
      final back = PlayerInfoFields.fromStored(stored);
      expect(back, contains('resolution'), reason: 'new and on by default');
      expect(back, isNot(contains('engine')), reason: 'new and off by default');
    });

    test('a field that no longer exists is dropped', () {
      final back = PlayerInfoFields.fromStored({
        'resolution': true,
        'dropped_frames_v1': true,
      });
      expect(back, isNot(contains('dropped_frames_v1')));
    });

    test('turning everything off is a real answer, kept as one', () {
      final back = PlayerInfoFields.fromStored(PlayerInfoFields.toStored({}));
      expect(back, isEmpty);
    });

    test('a round trip changes nothing', () {
      final chosen = {'resolution', 'engine', 'size'};
      expect(
        PlayerInfoFields.fromStored(PlayerInfoFields.toStored(chosen)),
        chosen,
      );
    });

    test('isDefault tracks the shipped set exactly', () {
      expect(PlayerInfoFields.isDefault(PlayerInfoFields.defaults), isTrue);
      expect(
        PlayerInfoFields.isDefault({...PlayerInfoFields.defaults, 'engine'}),
        isFalse,
      );
      expect(PlayerInfoFields.isDefault({}), isFalse);
    });
  });

  group('what the overlay then renders', () {
    List<PlaybackReadoutRow> rows({Set<String>? fields}) =>
        PlaybackReadout.rows(
          videoWidth: 1920,
          videoHeight: 1080,
          position: const Duration(minutes: 12),
          duration: const Duration(minutes: 47),
          bufferedTo: const Duration(minutes: 12, seconds: 30),
          playbackSpeed: 1.0,
          isLive: false,
          isBuffering: false,
          engineId: 'media_kit',
          providerId: 'anilist',
          streamUrl: 'https://cdn.example.test/a.m3u8',
          fields: fields,
        );

    test('only the chosen rows are built', () {
      final r = rows(fields: {'resolution'});
      expect(r.map((e) => e.id), ['resolution']);
    });

    test('an empty choice is an empty panel, not the default one', () {
      // `fields ?? defaults` alone would silently turn "I want none of this"
      // into "give me the usual five".
      expect(rows(fields: <String>{}), isEmpty);
    });

    test('null means the shipped set', () {
      final ids = rows().map((e) => e.id).toSet();
      expect(ids.every(PlayerInfoFields.defaults.contains), isTrue);
    });

    test('a chosen row with nothing to say is still left out', () {
      // Choosing a field is not a promise that a value exists for it — a
      // padded panel with a dash in it is worse than a short one.
      final r = rows(fields: {'resolution', 'server'});
      expect(r.map((e) => e.id), ['resolution']);
    });

    test('rows carry the id and the label that belongs to it', () {
      final r = rows(fields: {'resolution'}).single;
      expect(r.id, 'resolution');
      expect(r.labelKey, PlayerInfoFields.byId('resolution')!.labelKey);
    });
  });

  test('the domain layer stays free of Flutter', () {
    final source = File(
      'lib/features/detail/domain/playback/player_info_fields.dart',
    ).readAsStringSync();
    expect(source.contains('package:flutter/'), isFalse);
    expect(source.contains('get_it'), isFalse);
  });
}
