import 'package:dio/dio.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/notifications/data/datasources/notifications_data_source.dart';
import 'package:soplay/features/notifications/domain/entities/notification_item.dart';
import 'package:soplay/features/notifications/domain/repositories/notifications_repository.dart';

class NotificationsRepositoryImpl implements NotificationsRepository {
  final NotificationsDataSource dataSource;
  const NotificationsRepositoryImpl(this.dataSource);

  @override
  Future<Result<NotificationList>> list({
    int page = 1,
    int limit = 20,
    bool? unreadOnly,
  }) =>
      _wrap(() => dataSource.list(
            page: page,
            limit: limit,
            unreadOnly: unreadOnly,
          ));

  @override
  Future<Result<int>> unreadCount() => _wrap(dataSource.unreadCount);

  @override
  Future<Result<void>> markRead(String id) =>
      _wrap(() => dataSource.markRead(id));

  @override
  Future<Result<void>> markAllRead() => _wrap(dataSource.markAllRead);

  @override
  Future<Result<void>> delete(String id) => _wrap(() => dataSource.delete(id));

  @override
  Future<Result<void>> registerFcmToken({
    required String token,
    required String platform,
    required String language,
  }) =>
      _wrap(() => dataSource.registerFcmToken(
            token: token,
            platform: platform,
            language: language,
          ));

  @override
  Future<Result<void>> unregisterFcmToken(String token) =>
      _wrap(() => dataSource.unregisterFcmToken(token));

  Future<Result<T>> _wrap<T>(Future<T> Function() task) async {
    try {
      return Success(await task());
    } on DioException catch (e) {
      final data = e.response?.data;
      final raw = (data is Map ? data['message'] : null)?.toString() ??
          e.message ??
          'Xatolik yuz berdi';
      return Failure(Exception(raw));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }
}
