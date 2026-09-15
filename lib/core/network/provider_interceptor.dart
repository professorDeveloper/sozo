import 'package:dio/dio.dart';
import 'package:soplay/core/storage/hive_service.dart';

class ProviderInterceptor extends Interceptor {
  final HiveService hiveService;

  ProviderInterceptor({required this.hiveService});

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
    handler.next(options);
  }
}
