import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/player/drm_config.dart';

void main() {
  group('DrmScheme.fromId', () {
    test('accepts our own ids', () {
      expect(DrmScheme.fromId('clearkey'), DrmScheme.clearKey);
      expect(DrmScheme.fromId('widevine'), DrmScheme.widevine);
      expect(DrmScheme.fromId('playready'), DrmScheme.playReady);
    });

    test('accepts the EME key-system names too', () {
      // These are what a manifest and half the channel lists in the wild write.
      // Refusing them would mean an unplayable channel whose data was correct.
      expect(DrmScheme.fromId('org.w3.clearkey'), DrmScheme.clearKey);
      expect(DrmScheme.fromId('com.widevine.alpha'), DrmScheme.widevine);
      expect(DrmScheme.fromId('com.microsoft.playready'), DrmScheme.playReady);
      expect(DrmScheme.fromId('  ClearKey  '), DrmScheme.clearKey);
    });

    test('an unknown scheme is null, not a guess', () {
      // Guessing routes the stream to a backend that cannot decrypt it, and the
      // failure arrives four seconds into a black screen.
      expect(DrmScheme.fromId('fairplay'), isNull);
      expect(DrmScheme.fromId(''), isNull);
      expect(DrmScheme.fromId(null), isNull);
    });
  });

  group('fromJson', () {
    test('no drm block is no drm', () {
      expect(DrmConfig.fromJson(null), isNull);
      expect(DrmConfig.fromJson(const {}), isNull);
    });

    test('clearkey needs keys', () {
      // A scheme with nothing to decrypt with is worse than no block at all: it
      // sends the stream to the decrypting backend, which then fails, instead
      // of letting the ordinary player try a stream that may have played.
      expect(
        DrmConfig.fromJson(const {'scheme': 'clearkey'}),
        isNull,
      );
      final ok = DrmConfig.fromJson(const {
        'scheme': 'clearkey',
        'clearKeys': {'abc': 'def'},
      });
      expect(ok, isNotNull);
      expect(ok!.isUsable, isTrue);
    });

    test('widevine needs a licence url', () {
      expect(
        DrmConfig.fromJson(const {'scheme': 'widevine', 'clearKeys': {'a': 'b'}}),
        isNull,
        reason: 'keys are not a licence server',
      );
      expect(
        DrmConfig.fromJson(const {
          'scheme': 'widevine',
          'licenseUrl': 'https://lic.example/wv',
        }),
        isNotNull,
      );
    });

    test('licence headers survive', () {
      // An operator that gates its licence server on a token answers 403 while
      // the manifest loads fine, which presents as "the video is black".
      final c = DrmConfig.fromJson(const {
        'scheme': 'widevine',
        'licenseUrl': 'https://lic.example/wv',
        'licenseHeaders': {'X-Token': 'abc', 'Referer': 'https://example'},
      })!;
      expect(c.licenseHeaders['X-Token'], 'abc');
      expect(c.licenseHeaders['Referer'], 'https://example');
    });

    test('keys are read from every shape these arrive in', () {
      const kid = '00112233445566778899aabbccddeeff';
      const key = 'ffeeddccbbaa99887766554433221100';

      final asMap = DrmConfig.fromJson(const {
        'scheme': 'clearkey',
        'clearKeys': {kid: key},
      })!;
      // The "keys" spelling, which some lists use.
      final altName = DrmConfig.fromJson(const {
        'scheme': 'clearkey',
        'keys': {kid: key},
      })!;
      // A hand-written "kid:key" string, which is how these get pasted around.
      final asString = DrmConfig.fromJson(const {
        'scheme': 'clearkey',
        'clearKeys': '$kid:$key',
      })!;
      // A list of objects, which is the EME-ish shape.
      final asList = DrmConfig.fromJson(const {
        'scheme': 'clearkey',
        'clearKeys': [
          {'kid': kid, 'key': key},
        ],
      })!;

      for (final c in [asMap, altName, asString, asList]) {
        expect(c.clearKeys, {kid: key});
      }
    });

    test('several space-separated pairs all parse', () {
      final c = DrmConfig.fromJson(const {
        'scheme': 'clearkey',
        'clearKeys': 'aaaa:bbbb cccc:dddd',
      })!;
      expect(c.clearKeys, {'aaaa': 'bbbb', 'cccc': 'dddd'});
    });
  });

  group('toString', () {
    test('never prints key material', () {
      // This lands in the diagnostics log the player already writes, and that
      // log gets pasted into bug reports. It must not be a way to hand out
      // someone's content keys.
      final c = DrmConfig.fromJson(const {
        'scheme': 'clearkey',
        'clearKeys': {'00112233445566778899aabbccddeeff': 'secretkeymaterial'},
      })!;
      final printed = c.toString();
      expect(printed, isNot(contains('secretkeymaterial')));
      expect(printed, isNot(contains('00112233445566778899aabbccddeeff')));
      expect(printed, contains('clearkey'));
      expect(printed, contains('keys: 1'));
    });

    test('says whether a licence url is set without printing it', () {
      final c = DrmConfig.fromJson(const {
        'scheme': 'widevine',
        'licenseUrl': 'https://lic.example/secret-path?token=abc',
      })!;
      expect(c.toString(), isNot(contains('token=abc')));
      expect(c.toString(), contains('license: set'));
    });
  });

  group('toMap', () {
    test('round-trips through the channel', () {
      final c = DrmConfig.fromJson(const {
        'scheme': 'clearkey',
        'clearKeys': {'aa': 'bb'},
        'multiSession': true,
      })!;
      final back = DrmConfig.fromJson(c.toMap());
      expect(back, c);
    });
  });
}
