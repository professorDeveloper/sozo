import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:soplay/features/support/data/support_models.dart';

/// Tickets to and from support (backend: /api/support).
///
/// Every call carries this install's support key alongside whatever account
/// the app is signed in to. A guest's tickets belong to the key, and a guest
/// who signs in later still sees what they wrote before.
class SupportRepository {
  /// [deviceKey] is HiveService.supportDeviceKey in the app.
  SupportRepository({required Dio dio, required String Function() deviceKey})
    : _dio = dio,
      _deviceKey = deviceKey;

  final Dio _dio;
  final String Function() _deviceKey;

  Options get _options => Options(headers: {'X-Support-Key': _deviceKey()});

  Future<SupportInbox> list({int page = 1}) => _guard(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/support/tickets',
      queryParameters: {'page': page, 'limit': 30},
      options: _options,
    );
    final data = res.data ?? const {};
    final items = (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => SupportTicket.fromJson(m.cast<String, dynamic>()))
        .toList();
    return SupportInbox(
      tickets: items,
      unread: (data['unread'] as num?)?.toInt() ?? 0,
    );
  });

  Future<SupportTicket> get(String id) => _guard(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/support/tickets/$id',
      options: _options,
    );
    return _ticket(res.data);
  });

  Future<SupportTicket> create({
    required SupportCategory category,
    required String message,
    String? contact,
    Map<String, String>? diagnostics,
  }) => _guard(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/support/tickets',
      data: {
        'category': category.name,
        'message': message,
        if (contact != null && contact.trim().isNotEmpty)
          'contact': contact.trim(),
        if (diagnostics != null && diagnostics.isNotEmpty)
          'diagnostics': diagnostics,
      },
      options: _options,
    );
    return _ticket(res.data);
  });

  Future<SupportTicket> reply(String id, String message) => _guard(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/support/tickets/$id/messages',
      data: {'message': message},
      options: _options,
    );
    return _ticket(res.data);
  });

  Future<SupportTicket> close(String id) => _guard(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/support/tickets/$id/close',
      options: _options,
    );
    return _ticket(res.data);
  });

  SupportTicket _ticket(Map<String, dynamic>? data) {
    final raw = data?['ticket'];
    if (raw is! Map) throw SupportException('support.error_generic'.tr());
    return SupportTicket.fromJson(raw.cast<String, dynamic>());
  }

  /// The refusal in the viewer's language. The server's own messages are
  /// Uzbek, written for the admin panel, so only its codes are read here.
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      final body = e.response?.data;
      final code = body is Map ? body['code']?.toString() : null;
      final key = switch ((e.response?.statusCode, code)) {
        (429, _) => 'support.error_too_many',
        (_, 'SUPPORT_MESSAGE') => 'support.error_short',
        (_, 'SUPPORT_THREAD_FULL') => 'support.error_thread_full',
        (_, 'SUPPORT_NOT_FOUND') => 'support.error_not_found',
        _ => 'support.error_generic',
      };
      throw SupportException(key.tr(), code: code);
    }
  }
}
