import 'package:soplay/core/network/user_agent.dart';
import 'package:dio/dio.dart';

import 'cf_bypass_service.dart';

class CfBypassInterceptor extends Interceptor {
  static const String _skipKey = 'skipCfBypassInterceptor';
  static const String _retriedKey = 'cfBypassRetried';

  final Dio dio;
  final CfBypassService service;

  CfBypassInterceptor({required this.dio, required this.service});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final request = err.requestOptions;
    if (request.extra[_skipKey] == true || request.extra[_retriedKey] == true) {
      handler.next(err);
      return;
    }

    final isChallenge =
        err.response?.statusCode == 428 &&
        err.response?.data is Map &&
        (err.response!.data as Map)['cfChallenge'] == true;
    if (!isChallenge) {
      handler.next(err);
      return;
    }

    final data = err.response!.data as Map;
    final host = (data['host'] as String?)?.trim();
    final url = (data['url'] as String?)?.trim();
    final ua = (data['userAgent'] as String?)?.trim() ?? kSozoUserAgent;
    if (host == null || host.isEmpty || url == null || url.isEmpty) {
      handler.next(err);
      return;
    }

    final cookieHeader = await service.solve(
      host: host,
      url: url,
      userAgent: ua,
    );
    if (cookieHeader == null) {
      handler.next(err);
      return;
    }

    try {
      await dio.post(
        '/cf-cookies',
        data: {'host': host, 'cookies': cookieHeader, 'userAgent': ua},
        options: Options(extra: const {_skipKey: true}),
      );
    } catch (_) {
      handler.next(err);
      return;
    }

    request.extra[_retriedKey] = true;
    try {
      final retry = await dio.fetch(request);
      handler.resolve(retry);
    } on DioException catch (e) {
      handler.next(e);
    } catch (_) {
      handler.next(err);
    }
  }
}
