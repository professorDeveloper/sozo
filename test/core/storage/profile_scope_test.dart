import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/network/profile_interceptor.dart';
import 'package:soplay/core/storage/profile_scope.dart';

void main() {
  tearDown(ProfileScope.reset);

  group('default profile', () {
    test('uses exactly the box names every install already has', () {
      for (final base in ProfileScope.profileBoxes) {
        expect(ProfileScope.box(base), base);
      }
    });

    test('uses exactly the settings keys every install already has', () {
      for (final key in ProfileScope.profileKeys) {
        expect(ProfileScope.key(key), key);
      }
    });
  });

  group('extra profile', () {
    setUp(() => ProfileScope.set(namespace: 'abc123', remoteId: 'abc123'));

    test('gets suffixed boxes for personal data', () {
      expect(
        ProfileScope.box(AppConstants.historyBox),
        'history_box__p_abc123',
      );
      expect(
        ProfileScope.box(AppConstants.privateFavoritesBox),
        'private_favorites_box__p_abc123',
      );
    });

    test('shares device-level boxes', () {
      for (final base in const [
        AppConstants.settingsBox,
        AppConstants.authBox,
        AppConstants.downloadBox,
        AppConstants.extractorsBox,
        AppConstants.streakBox,
      ]) {
        expect(ProfileScope.box(base), base);
      }
    });

    test('suffixes personal settings keys and leaves the rest alone', () {
      expect(
        ProfileScope.key(AppConstants.incognitoKey),
        'incognito_mode@p_abc123',
      );
      expect(ProfileScope.isProfileKey('incognito_mode@p_abc123'), isTrue);
      expect(ProfileScope.key(AppConstants.languageKey), 'language');
      expect(ProfileScope.key(AppConstants.themeModeKey), 'theme_mode');
      expect(ProfileScope.key('tracker_outbox'), 'tracker_outbox');
    });
  });

  group('ProfileInterceptor', () {
    Future<RequestOptions> send() async {
      RequestOptions? seen;
      final dio = Dio()
        ..interceptors.add(ProfileInterceptor())
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) {
              seen = o;
              h.resolve(Response(requestOptions: o, statusCode: 200));
            },
          ),
        );
      await dio.get('https://example.invalid/auth/history');
      return seen!;
    }

    test(
      'sends nothing before a profile is known, like an old build',
      () async {
        final o = await send();
        expect(o.headers.containsKey(ProfileInterceptor.header), isFalse);
      },
    );

    test('names the active profile, the default one included', () async {
      ProfileScope.set(remoteId: 'main1');
      expect((await send()).headers[ProfileInterceptor.header], 'main1');
      ProfileScope.set(namespace: 'kid1', remoteId: 'kid1', kids: true);
      expect((await send()).headers[ProfileInterceptor.header], 'kid1');
    });

    test('reports a profile the server no longer has', () async {
      ProfileScope.set(namespace: 'gone', remoteId: 'gone');
      var stale = 0;
      final dio = Dio()
        ..interceptors.add(ProfileInterceptor(onStaleProfile: () => stale++))
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) => h.reject(
              DioException(
                requestOptions: o,
                response: Response(
                  requestOptions: o,
                  statusCode: 404,
                  data: {'code': 'PROFILE_NOT_FOUND'},
                ),
              ),
              true,
            ),
          ),
        );
      await expectLater(
        dio.get('https://example.invalid/auth/favorites'),
        throwsA(isA<DioException>()),
      );
      expect(stale, 1);
    });
  });
}
