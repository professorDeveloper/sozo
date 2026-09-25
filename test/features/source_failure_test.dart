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
      final f = SourceFailure.of(
        'Aniyomi: getPopular: HttpException: HTTP error 404',
      );
      expect(f.detail, 'Aniyomi: getPopular: HttpException: HTTP error 404');
      expect(f.headline, isNot(contains('HttpException')));
    });

    test(
      'a reflection wrapper reads as the source failing, not as plumbing',
      () {
        final f = SourceFailure.of(
          'instantiate en.anikage.Anikage: InvocationTargetException',
        );
        expect(f.headline, isNot(contains('InvocationTargetException')));
        expect(f.detail, contains('InvocationTargetException'));
      },
    );

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
          reason:
              'classified as ${f.kind} — the reader is told the source is '
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
      final f = SourceFailure.of(
        'Exception: Manga: source unavailable: mn:497',
      );
      expect(f.headline, 'Manga: source unavailable: mn:497');
      expect(f.headline, isNot(contains('Exception:')));
    });

    test('an unrecognised failure is not repeated underneath itself', () {
      final f = SourceFailure.of(
        'Exception: Manga: source unavailable: mn:497',
      );
      expect(f.detail, isNull);
    });

    test('a doubled prefix is stripped too', () {
      expect(SourceFailure.of('Exception: Exception: boom').headline, 'boom');
    });
  });

  // Two manga sources, measured on a real device, whose whole home screen was a
  // Kotlin exception.
  group('what a manga reader actually fails with', () {
    test('a site that changed its shape asks for the SOURCE to be updated', () {
      // Tachiyomi parses the site's JSON into a declared shape, so a field the
      // site drops throws this. It is not the app, not the network and not the
      // site being down — the extension's repo usually already has the build
      // that reads it.
      final f = SourceFailure.of(
        'kotlinx.serialization.MissingFieldException: Fields [artists, authors, '
        "relationships, groups, parodies, characters] are required for type with "
        "serial name 'eu.kanade.tachiyomi.multisrc.hentaihand.MangaDto', but "
        r'they were missing at path: $.data[0]',
      );
      expect(f.kind, SourceFailureKind.outdated);
      expect(f.headline, isNot(contains('MissingFieldException')));
      expect(
        f.detail,
        contains('MangaDto'),
        reason: 'the raw line is the bug report',
      );
    });

    test('and that is not the same as needing a newer app', () {
      // [incompatible] is the app and the extension disagreeing; this is the
      // extension and its own site. Different fix, so it cannot be the same
      // sentence.
      expect(
        SourceFailure.of('NoSuchMethodError: getVideoTitle()').kind,
        SourceFailureKind.incompatible,
      );
    });

    test('a message written for the reader arrives as a sentence', () {
      // A gallery source has no browse feed at all and says so, in words, in
      // the exception. That is the most useful thing anything said about that
      // screen and it was rendered as a crash.
      final f = SourceFailure.of(
        'java.lang.UnsupportedOperationException: Please enter a query in the '
        'format of gallery:{username} or gallery:{username}/{folderId}',
      );
      expect(f.headline, startsWith('Please enter a query'));
      expect(f.headline, isNot(contains('java.lang')));
    });

    test('but a class name with nothing readable after it keeps its name', () {
      // Then the class name is all the information there is, and a bare token
      // in its place tells the reader strictly less.
      expect(
        SourceFailure.of('com.example.WeirdException: nope').headline,
        contains('WeirdException'),
      );
      expect(
        SourceFailure.of('com.example.OddError: mn:497').headline,
        contains('OddError'),
      );
    });

    test('and unwrapping never hides a word a classifier needs', () {
      // Every rule above keys on exactly these class names, so unwrapping
      // before them would turn a recognised failure into an unrecognised one.
      expect(
        SourceFailure.of(
          'java.net.UnknownHostException: Unable to resolve host "manga.test"',
        ).kind,
        SourceFailureKind.unreachable,
      );
      expect(
        SourceFailure.of(
          'java.lang.NullPointerException: Attempt to read a field on a null '
          'object reference',
        ).kind,
        SourceFailureKind.broken,
      );
    });

    test('a stack trace under the message is not part of the message', () {
      final f = SourceFailure.of(
        'java.lang.UnsupportedOperationException: Please enter a query first\n'
        '\tat eu.kanade.tachiyomi.source.online.HttpSource.getPopularManga',
      );
      expect(f.headline, 'Please enter a query first');
    });
  });
}
