import 'package:dio/dio.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/auth/data/models/user_model.dart';

class TvPairing {
  const TvPairing({
    required this.deviceCode,
    required this.userCode,
    required this.expiresAt,
    required this.interval,
  });

  final String deviceCode;
  final String userCode;
  final DateTime expiresAt;
  final Duration interval;

  /// What the phone's camera opens: the link-a-TV page with the code filled.
  String get link => 'https://sozo.azamov.me/link/$userCode';
}

enum TvPairingStatus { pending, approved, expired }

/// Signing a television in from a phone: the TV shows a code, the phone
/// approves it on /link-tv, and the TV collects its tokens by polling.
class TvPairingService {
  TvPairingService({required this.dio, required this.hive});

  final Dio dio;
  final HiveService hive;

  Future<TvPairing> create({String deviceName = 'Sozo TV'}) async {
    final res = await dio.post(
      '/auth/device/code',
      data: {'deviceName': deviceName},
    );
    final data = Map<String, dynamic>.from(res.data as Map);
    final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 600;
    final interval = (data['interval'] as num?)?.toInt() ?? 5;
    return TvPairing(
      deviceCode: data['device_code'] as String,
      userCode: data['user_code'] as String,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      interval: Duration(seconds: interval.clamp(2, 30)),
    );
  }

  /// One poll. On approval the tokens are saved, so the caller only has to
  /// tell the auth bloc to pick them up.
  Future<TvPairingStatus> poll(TvPairing pairing) async {
    if (DateTime.now().isAfter(pairing.expiresAt)) {
      return TvPairingStatus.expired;
    }
    final res = await dio.post(
      '/auth/device/token',
      data: {'device_code': pairing.deviceCode},
    );
    final data = Map<String, dynamic>.from(res.data as Map);
    switch (data['status']) {
      case 'approved':
        final user = data['user'];
        await hive.saveAuth(
          accessToken: data['accessToken'] as String,
          refreshToken: data['refreshToken'] as String,
          user: UserModel.fromJson(
            user is Map ? user.cast<String, dynamic>() : const {},
          ),
        );
        return TvPairingStatus.approved;
      case 'expired':
        return TvPairingStatus.expired;
      default:
        return TvPairingStatus.pending;
    }
  }
}
