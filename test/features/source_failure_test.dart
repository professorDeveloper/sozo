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
