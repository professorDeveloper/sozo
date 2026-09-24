import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:soplay/core/storage/profile_scope.dart';

/// Tells the backend which household profile a request acts as.
class ProfileInterceptor extends Interceptor {
  ProfileInterceptor({this.onStaleProfile});

  static const String header = 'X-Sozo-Profile';

  /// The profile was deleted on another device. Data routes refuse such a
  /// request rather than use the default profile's data, so the app has to
  /// fall back itself.
  final VoidCallback? onStaleProfile;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final id = ProfileScope.remoteId;
    if (id != null && id.isNotEmpty) options.headers[header] = id;
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final res = err.response;
    final data = res?.data;
    if (res?.statusCode == 404 &&
        data is Map &&
        data['code'] == 'PROFILE_NOT_FOUND' &&
        err.requestOptions.headers[header] == ProfileScope.remoteId) {
      onStaleProfile?.call();
    }
    handler.next(err);
  }
}
