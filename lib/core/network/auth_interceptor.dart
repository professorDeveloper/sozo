import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:soplay/core/storage/hive_service.dart';

/// What a refresh attempt concluded, which is not the same question as
/// whether it produced a token.
///
/// Signing the session out deletes the account's history, lists, tracker links
/// and streak from the device — see `AuthBloc._onSessionExpired`, which does
/// that on purpose so the next person to pick the phone up cannot read them.
/// That is the right answer to "the server says this refresh token is dead"
/// and a catastrophic one to "we could not reach the server", and a bare
/// `catch (_) { return null; }` could not tell them apart.
enum _RefreshOutcome {
  /// A new access token is saved and the request can be retried.
  refreshed,

  /// The server answered, and the answer was no. The session is over.
  rejected,

  /// Nobody answered: no connection, a timeout, a 5xx, a proxy. Says nothing
  /// about whether the session is still good.
  unreachable,
}

class AuthInterceptor extends Interceptor {
  static const _skipKey = 'skipAuthInterceptor';
  static const _retriedKey = 'authRetried';

  final HiveService hiveService;
  final Dio dio;
  final VoidCallback? onSessionExpired;

  Future<(String?, _RefreshOutcome)>? _refreshFuture;

  AuthInterceptor({
    required this.hiveService,
    required this.dio,
    this.onSessionExpired,
  });

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.extra[_skipKey] == true) {
      handler.next(options);
      return;
    }
    final token = hiveService.getToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final request = err.requestOptions;
    final isRefreshCall = request.path.contains('/auth/refresh');
    final alreadyRetried = request.extra[_retriedKey] == true;
    final isSkipped = request.extra[_skipKey] == true;

    if (err.response?.statusCode != 401 ||
        isRefreshCall ||
        alreadyRetried ||
        isSkipped) {
      handler.next(err);
      return;
    }

    final refreshToken = hiveService.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await _expireSession();
      handler.next(err);
      return;
    }

    final staleAuth = request.headers['Authorization'];
    final (newAccess, outcome) = await _refresh(refreshToken);
    if (newAccess == null) {
      // Our refresh may have failed only because a concurrent refresher (e.g.
      // the watch-party socket's TokenRefresher) already rotated the refresh
      // token and saved a fresh access token. Don't wipe auth / log out in that
      // case — retry the request with the current token instead.
      final current = hiveService.getToken();
      if (current != null &&
          current.isNotEmpty &&
          'Bearer $current' != staleAuth) {
        request.headers['Authorization'] = 'Bearer $current';
        request.extra[_retriedKey] = true;
        try {
          final retryResponse = await dio.fetch(request);
          handler.resolve(retryResponse);
        } on DioException catch (e) {
          handler.next(e);
        } catch (_) {
          handler.next(err);
        }
        return;
      }
      // Only a refusal ends the session. When nobody answered, the token we
      // hold may be perfectly good and the network simply is not there — so
      // the original 401 goes back to the caller and everything on the device
      // stays where it is, to be tried again on the next request.
      if (outcome == _RefreshOutcome.rejected) await _expireSession();
      handler.next(err);
      return;
    }

    request.headers['Authorization'] = 'Bearer $newAccess';
    request.extra[_retriedKey] = true;

    try {
      final retryResponse = await dio.fetch(request);
      handler.resolve(retryResponse);
    } on DioException catch (e) {
      handler.next(e);
    } catch (_) {
      handler.next(err);
    }
  }

  Future<(String?, _RefreshOutcome)> _refresh(String refreshToken) {
    _refreshFuture ??= _performRefresh(refreshToken).whenComplete(() {
      _refreshFuture = null;
    });
    return _refreshFuture!;
  }

  Future<(String?, _RefreshOutcome)> _performRefresh(
    String refreshToken,
  ) async {
    try {
      final response = await dio.post(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
        options: Options(extra: const {_skipKey: true}),
      );
      final data = response.data as Map<String, dynamic>;
      final newAccess = data['accessToken'] as String? ?? '';
      final newRefresh = data['refreshToken'] as String? ?? refreshToken;
      // A 200 with no token in it is the server refusing in a roundabout way.
      if (newAccess.isEmpty) return (null, _RefreshOutcome.rejected);
      await hiveService.saveTokens(
        accessToken: newAccess,
        refreshToken: newRefresh,
      );
      return (newAccess, _RefreshOutcome.refreshed);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      // Only the server turning the token down ends the session. A 5xx is the
      // server being broken, and a DioException with no response at all never
      // reached it — neither is evidence about the token, and treating them as
      // if they were is how a tunnel signs somebody out and wipes their
      // history on the way.
      final rejected = code != null && code >= 400 && code < 500;
      return (null, rejected ? _RefreshOutcome.rejected : _RefreshOutcome.unreachable);
    } catch (_) {
      return (null, _RefreshOutcome.unreachable);
    }
  }

  Future<void> _expireSession() async {
    await hiveService.clearAuth();
    onSessionExpired?.call();
  }
}
