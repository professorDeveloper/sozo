import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/extensions/data/mangayomi_bridge.dart';
import 'package:soplay/features/home/data/datasources/home_data_source.dart';
import 'package:soplay/features/home/data/repositories/home_repository_imp.dart';

class _Hive implements HiveService {
  _Hive(this.provider);
  final String provider;
  @override
  String getCurrentProvider() => provider;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Bridge implements MangayomiBridge {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final kind in ['anilist', 'anilist-manga', 'anilist-novel', 'tmdb']) {
    test('Home genre pagination uses the $kind catalogue route', () async {
      final dio = Dio();
      final paths = <String>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            paths.add(options.path);
            if (options.path.startsWith('/contents/')) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 400,
                    data: {'message': 'Unknown provider "cat:$kind".'},
                  ),
                ),
              );
            } else {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'provider': 'cat:$kind',
                    'items': [],
                    'page': options.queryParameters['page'],
                    'totalPages': 3,
                  },
                ),
              );
            }
          },
        ),
      );
      final repo = HomeRepositoryImp(
        HomeDataSource(dio: dio),
        hive: _Hive('cat:$kind'),
        mangayomi: _Bridge(),
      );
      final result = await repo.loadViewAll(
        key: 'genre',
        slug: 'action',
        page: 2,
      );
      expect(
        result.isSuccess,
        isTrue,
        reason: result.getErrorOrNull()?.toString(),
      );
      expect(paths, ['/catalogue/$kind/genre/action']);
      expect(result.getOrNull()!.page, 2);
    });
  }
}
