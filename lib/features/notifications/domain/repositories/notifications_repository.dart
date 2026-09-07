import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/notifications/domain/entities/notification_item.dart';

abstract class NotificationsRepository {
  Future<Result<NotificationList>> list({
    int page = 1,
    int limit = 20,
    bool? unreadOnly,
  });

  Future<Result<int>> unreadCount();

  Future<Result<void>> markRead(String id);

  Future<Result<void>> markAllRead();

  Future<Result<void>> delete(String id);

  Future<Result<void>> registerFcmToken({
    required String token,
    required String platform,
    required String language,
  });

  Future<Result<void>> unregisterFcmToken(String token);
}
