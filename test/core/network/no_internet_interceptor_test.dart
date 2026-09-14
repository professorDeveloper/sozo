import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/network/no_internet_interceptor.dart';

class _OfflineAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => throw DioException(
    requestOptions: options,
    type: DioExceptionType.connectionError,
    error: const SocketException('Offline'),
  );
  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'background API failure is delivered without constructing or changing the app router',
    () async {
      final dio = Dio()..httpClientAdapter = _OfflineAdapter();
      dio.interceptors.add(NoInternetInterceptor());
      addTearDown(dio.close);
      await expectLater(
        dio.get('https://fixture.invalid/catalog/sources'),
        throwsA(isA<DioException>()),
      );
      // A former unawaited redirect tried to instantiate AppRouter here and
      // abandoned the caller's local source/reader page after the probe.
      await Future<void>.delayed(Duration.zero);
    },
  );
}
