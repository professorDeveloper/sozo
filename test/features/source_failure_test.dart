import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soplay/features/sources/domain/source_failure.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  _prefixTests();

  group('SourceFailure', () {
    test('a 404 is a site that is gone, and keeps the original underneath', () {
      final f = SourceFailure.of('Aniyomi: getPopular: HttpException: HTTP error 404');
      expect(f.detail, 'Aniyomi: getPopular: HttpException: HTTP error 404');
      expect(f.headline, isNot(contains('HttpException')));
    });

    test('a reflection wrapper reads as the source failing, not as plumbing', () {
      final f = SourceFailure.of('instantiate en.anikage.Anikage: InvocationTargetException');
      expect(f.headline, isNot(contains('InvocationTargetException')));
      expect(f.detail, contains('InvocationTargetException'));
    });

    test('a linkage error asks for a newer app', () {
      final gone = SourceFailure.of('No virtual method getHosterList');
      final linkage = SourceFailure.of('NoSuchMethodError: getVideoTitle()');
      expect(linkage.headline, isNot(equals(gone.headline)));
      expect(linkage.detail, contains('NoSuchMethodError'));
    });

    test('an unrecognised failure is shown as it was, not guessed at', () {
      const raw = 'something nobody has seen before';
      final f = SourceFailure.of(raw);
      expect(f.headline, raw);
      expect(f.detail, isNull);
    });

    test('a status code inside an id is not read as a status code', () {
      // The digits are there, but not as their own token — a content id, not
      // a 404. Guessing "this site is gone" from that would be worse than
      // saying nothing.
      final f = SourceFailure.of('failed for id 1404042');
      expect(f.headline, 'failed for id 1404042');
      expect(f.detail, isNull);
    });

    test('nothing at all still says something', () {
      expect(SourceFailure.of(null).headline, isNotEmpty);
      expect(SourceFailure.of('   ').headline, isNotEmpty);
    });
  });
}

void _prefixTests() {
  group('SourceFailure speaks both sides of the platform channel', () {
    // A source failure arrives in whichever language the layer that threw it
    // speaks: the JVM's, from an extension on Android, or Dart's and Dio's,
    // from the app's own client. Only the JVM half was recognised, so being
    // offline — the single most common failure there is — came out as
    // `unknown` and put a `DioException` on the screen.
    //
    // These are the real strings, not invented ones.
    const dartSide = <String>[
      "SocketException: Failed host lookup: 'api.example.com' "
          '(OS Error: nodename nor servname provided, or not known, errno = 8)',
      'DioException [connection error]: The connection errored: '
          'Connection refused',
      'DioException [connection timeout]: The request connection took longer '
          'than 0:00:15.000000',
      'DioException [receive timeout]: The request took longer than '
          '0:00:20.000000 to receive data',
      'SocketException: Connection reset by peer',
      'HandshakeException: Connection terminated during handshake',
    ];

    for (final raw in dartSide) {
      test('offline reads as unreachable: ${raw.split(':').first}', () {
        final f = SourceFailure.of(raw);
        expect(
          f.kind,
          SourceFailureKind.unreachable,
          reason: 'classified as ${f.kind} — the reader is told the source is '
              'broken when in fact their connection is:\n$raw',
        );
        expect(f.headline, isNot(contains('Exception')));
        expect(f.detail, contains(raw));
      });
    }

    test('a Dio status code still beats the connection wording', () {
      // Dio phrases a 404 as an "invalid status code", with no word from the
      // unreachable list in it — but the ordering is what guarantees that,
      // and the ordering is easy to lose.
      final f = SourceFailure.of(
        'DioException [bad response]: This exception was thrown because the '
        'response has a status code of 404.',
      );
      expect(f.kind, SourceFailureKind.gone);
    });
  });

  group('SourceFailure is a value', () {
    test('two failures that say the same thing are the same state', () {
      // Blocs carry one in their state. Compared by identity, every rebuild
      // reported a change.
      expect(
        SourceFailure.of('SocketException: Failed host lookup'),
        SourceFailure.of('SocketException: Failed host lookup'),
      );
    });

    test('and two that do not, are not', () {
      expect(
        SourceFailure.of('HTTP error 404'),
        isNot(SourceFailure.of('HTTP error 403')),
      );
    });
  });

  group('SourceFailure prefixes', () {
    test("Dart's own Exception: prefix is not part of the message", () {
      final f = SourceFailure.of('Exception: Manga: source unavailable: mn:497');
      expect(f.headline, 'Manga: source unavailable: mn:497');
      expect(f.headline, isNot(contains('Exception:')));
    });

    test('an unrecognised failure is not repeated underneath itself', () {
      final f = SourceFailure.of('Exception: Manga: source unavailable: mn:497');
      expect(f.detail, isNull);
    });

    test('a doubled prefix is stripped too', () {
      expect(
        SourceFailure.of('Exception: Exception: boom').headline,
        'boom',
      );
    });
  });
}
