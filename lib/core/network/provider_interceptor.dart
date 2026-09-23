import 'package:dio/dio.dart';
import 'package:soplay/core/storage/hive_service.dart';

class ProviderInterceptor extends Interceptor {
  final HiveService hiveService;

  ProviderInterceptor({required this.hiveService});

  /// Present, as `1`, when the viewer has chosen to see adult content.
  static const String adultHeader = 'X-Sozo-Adult';

  static const Set<String> _excludedContentsPaths = {
    '/contents/media',
    '/contents/providers',
    '/contents/providers/health',
  };

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final path = options.path;
    final shouldAttach =
        path.startsWith('/contents/') &&
        !_excludedContentsPaths.contains(path) &&
        !options.queryParameters.containsKey('provider');

    if (shouldAttach) {
      options.queryParameters['provider'] = hiveService.getCurrentProvider();
    }
    // The 18+ setting, on every request: the backend's catalogues — AniList,
    // TMDB — decide what to include from it. A header rather than a query
    // parameter so no endpoint has to be taught to pass it along, and so it
    // is present on the ones nobody thought would need it.
    if (hiveService.showAdultContent) {
      options.headers[adultHeader] = '1';
    }
    handler.next(options);
  }
}
