import 'dart:io';

import 'package:soplay/core/error/result.dart';

import '../entities/auth_token.dart';
import '../entities/user_entity.dart';

abstract class AuthRepository {
  Future<Result<AuthToken>> login(String identifier, String password);

  Future<Result<AuthToken>> loginWithGoogle(String idToken);

  Future<Result<void>> requestRegisterOtp({
    required String email,
    required String username,
    required String password,
  });

  Future<Result<void>> resendRegisterOtp(String email);

  Future<Result<AuthToken>> verifyRegisterOtp({
    required String email,
    required String code,
  });

  Future<Result<void>> requestPasswordReset(String email);

  Future<Result<AuthToken>> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  });

  Future<Result<UserEntity>> getProfile();

  Future<Result<UserEntity>> updateProfile({
    String? username,
    String? displayName,
    String? photoUrl,
  });

  /// Puts [file] in R2 and answers with the url the picture now lives at.
  Future<Result<String>> uploadAvatar(File file);

  Future<void> logout();

  /// Wipes everything the signed-in account left on this device, without
  /// asking the server — for when the server has already ended the session.
  Future<void> clearLocalSession();
}
