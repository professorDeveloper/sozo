import 'package:dio/dio.dart';
import 'package:soplay/features/notifications/data/models/notification_item_model.dart';

class NotificationsDataSource {
  final Dio dio;
  const NotificationsDataSource({required this.dio});

  Future<NotificationListModel> list({
    int page = 1,
    int limit = 20,
    bool? unreadOnly,
  }) async {
    final res = await dio.get(
      '/notifications',
      queryParameters: {
        'page': page,
        'limit': limit,
        if (unreadOnly == true) 'unread': true,
      },
    );
    return NotificationListModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<int> unreadCount() async {
    final res = await dio.get('/notifications/unread-count');
    final data = res.data as Map<String, dynamic>;
    return (data['count'] as num?)?.toInt() ?? 0;
  }

  Future<void> markRead(String id) async {
    await dio.post('/notifications/$id/read');
  }

  Future<void> markAllRead() async {
    await dio.post('/notifications/read-all');
  }

  Future<void> delete(String id) async {
    await dio.delete('/notifications/$id');
  }

  Future<void> registerFcmToken({
    required String token,
    required String platform,
    required String language,
  }) async {
    await dio.post(
      '/notifications/fcm/register',
      data: {'token': token, 'platform': platform, 'language': language},
    );
  }

  Future<void> unregisterFcmToken(String token) async {
    await dio.post(
      '/notifications/fcm/unregister',
      data: {'token': token},
      options: Options(extra: const {'skipAuthInterceptor': true}),
    );
  }
}
