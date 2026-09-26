import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:soplay/features/support/data/support_models.dart';

/// Tickets to and from support (backend: /api/support).
///
/// Every call carries this install's support key alongside whatever account
/// the app is signed in to. A guest's tickets belong to the key, and a guest
/// who signs in later still sees what they wrote before.
class SupportRepository {
  /// [deviceKey] is HiveService.supportDeviceKey in the app; [pushToken] the
  /// device's FCM token, sent with each message so that an answer reaches a
  /// guest too; [uploads] the bare client screenshots go to R2 with.
  SupportRepository({
    required Dio dio,
    required String Function() deviceKey,
    Future<String?> Function()? pushToken,
    Dio? uploads,
  }) : _dio = dio,
       _deviceKey = deviceKey,
       _pushToken = pushToken,
       _uploads = uploads ?? Dio();

  final Dio _dio;
  final String Function() _deviceKey;
  final Future<String?> Function()? _pushToken;

  /// No base URL and no interceptors: the presigned URL carries its own
  /// authorisation, and the app's bearer token has no business reaching R2.
  final Dio _uploads;

  /// The server's limits (models/SupportTicket.js).
  static const int maxAttachments = 5;
  static const int maxAttachmentBytes = 5 * 1024 * 1024;

  static String? contentTypeFor(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.webp')) return 'image/webp';
    return null;
  }

  Future<String?> _token() async {
    try {
      return await _pushToken?.call();
    } catch (_) {
      return null;
    }
  }

  /// Puts one screenshot into R2 and returns the key a message carries it by.
  Future<String> uploadScreenshot(File file) async {
    final type = contentTypeFor(file.path);
    if (type == null) {
      throw SupportException('support.error_attachment_type'.tr());
    }
    final size = await file.length();
    if (size > maxAttachmentBytes) {
      throw SupportException('support.error_attachment_size'.tr());
    }
    final slot = await _guard(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/support/uploads',
        data: {'contentType': type, 'size': size},
        options: _options,
      );
      return res.data ?? const {};
    });
    final url = slot['uploadUrl'];
    final key = slot['key'];
    if (url is! String || key is! String) {
      throw SupportException('support.error_attachment'.tr());
    }
    try {
      // The length is signed into the URL: R2 refuses any other.
      await _uploads.put<void>(
        url,
        data: file.openRead(),
        options: Options(
          headers: {
            Headers.contentTypeHeader: type,
            Headers.contentLengthHeader: size,
          },
        ),
      );
    } on DioException {
      throw SupportException('support.error_attachment'.tr());
    }
    return key;
  }

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
    List<String> attachments = const [],
    String? language,
  }) => _guard(() async {
    final token = await _token();
    final res = await _dio.post<Map<String, dynamic>>(
      '/support/tickets',
      data: {
        'category': category.name,
        'message': message,
        if (contact != null && contact.trim().isNotEmpty)
          'contact': contact.trim(),
        if (diagnostics != null && diagnostics.isNotEmpty)
          'diagnostics': diagnostics,
        if (attachments.isNotEmpty) 'attachments': attachments,
        'language': ?language,
        'pushToken': ?token,
      },
      options: _options,
    );
    return _ticket(res.data);
  });

  Future<SupportTicket> reply(
    String id,
    String message, {
    List<String> attachments = const [],
    String? language,
  }) => _guard(() async {
    final token = await _token();
    final res = await _dio.post<Map<String, dynamic>>(
      '/support/tickets/$id/messages',
      data: {
        'message': message,
        if (attachments.isNotEmpty) 'attachments': attachments,
        'language': ?language,
        'pushToken': ?token,
      },
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
        (_, 'SUPPORT_ATTACHMENT_TYPE') => 'support.error_attachment_type',
        (_, 'SUPPORT_ATTACHMENT_SIZE') => 'support.error_attachment_size',
        (_, 'SUPPORT_ATTACHMENT_COUNT') => 'support.error_attachment_count',
        (_, 'SUPPORT_ATTACHMENT') => 'support.error_attachment',
        _ => 'support.error_generic',
      };
      throw SupportException(key.tr(), code: code);
    }
  }
}
