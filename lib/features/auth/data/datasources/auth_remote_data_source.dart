import 'package:dio/dio.dart';
import 'package:soplay/core/network/auth_interceptor.dart';
import '../models/auth_model.dart';
import '../models/user_model.dart';

class AuthRemoteDataSource {
  final Dio dio;

  const AuthRemoteDataSource({required this.dio});

  Future<AuthModel> login(String identifier, String password) async {
    final response = await dio.post(
      '/auth/login',
      data: {'identifier': identifier, 'password': password},
    );
    return AuthModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Trades a Firebase ID token for a Sozo session.
  Future<AuthModel> loginWithGoogle(String idToken) async {
    final response = await dio.post('/auth/google', data: {'idToken': idToken});
    return AuthModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> requestRegisterOtp({
    required String email,
    required String username,
    required String password,
  }) async {
    await dio.post(
      '/auth/register',
      data: {'email': email, 'username': username, 'password': password},
    );
  }

  Future<void> resendRegisterOtp(String email) async {
    await dio.post('/auth/register/resend', data: {'email': email});
  }

  Future<AuthModel> verifyRegisterOtp({
    required String email,
    required String code,
  }) async {
    final response = await dio.post(
      '/auth/register/verify',
      data: {'email': email, 'otp': code},
    );
    return AuthModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Asks the server to email a reset code.
  ///
  /// Answers the same way whether or not the address exists — the server
  /// decides that, and it deliberately does not say, so this must not treat a
  /// missing account as an error either.
  Future<void> requestPasswordReset(String email) async {
    await dio.post('/auth/forgot-password', data: {'email': email});
  }

  /// Sets the new password and returns the session it issues.
  ///
  /// The server signs the user in as part of the reset, so there is no second
  /// login round trip — and no window where they know the new password but the
  /// app still holds the old session.
  Future<AuthModel> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final response = await dio.post(
      '/auth/reset-password',
      data: {'email': email, 'otp': code, 'newPassword': newPassword},
    );
    return AuthModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<UserModel> getProfile() async {
    final response = await dio.get('/auth/profile');
    final data = response.data as Map<String, dynamic>;
    final userJson = data['user'] as Map<String, dynamic>? ?? data;
    return UserModel.fromJson(userJson);
  }

  Future<UserModel> updateProfile({
    String? username,
    String? displayName,
    String? photoUrl,
  }) async {
    final response = await dio.put(
      '/auth/profile',
      data: {
        'username': ?username,
        'displayName': ?displayName,
        'photoURL': ?photoUrl,
      },
    );
    final data = response.data as Map<String, dynamic>;
    final userJson = data['user'] as Map<String, dynamic>? ?? data;
    return UserModel.fromJson(userJson);
  }

  /// Asks for a slot in R2 and returns where to PUT the bytes and what the
  /// picture will be reachable at once they are there.
  Future<({String uploadUrl, String publicUrl})> avatarUploadUrl(
    String contentType,
  ) async {
    final response = await dio.post(
      '/auth/profile/avatar-url',
      data: {'contentType': contentType},
    );
    final data = response.data as Map<String, dynamic>;
    return (
      uploadUrl: data['uploadUrl'] as String,
      publicUrl: data['publicUrl'] as String,
    );
  }

  Future<Map<String, String>> refresh(String refreshToken) async {
    final response = await dio.post(
      '/auth/refresh',
      data: {'refreshToken': refreshToken},
    );
    final data = response.data as Map<String, dynamic>;
    return {
      'accessToken': data['accessToken'] as String? ?? '',
      'refreshToken': data['refreshToken'] as String? ?? refreshToken,
    };
  }

  Future<void> logout({String? refreshToken}) async {
    // A paired TV's session is its own record, ended by its refresh token;
    // /auth/logout would leave it valid and clear the phone's legacy session.
    if (refreshToken != null && isDeviceRefreshToken(refreshToken)) {
      await dio.post(
        '/auth/device/logout',
        data: {'refreshToken': refreshToken},
      );
      return;
    }
    await dio.post('/auth/logout');
  }
}
