import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/my_list/data/datasources/my_list_local_data_source.dart';
import 'package:soplay/features/stats/data/watch_stats_store.dart';
import 'package:soplay/features/streak/data/streak_service.dart';
import 'package:soplay/features/auth/data/models/user_model.dart';
import 'package:soplay/features/auth/domain/entities/auth_token.dart';
import 'package:soplay/features/auth/domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_data_source.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/features/history/data/history_sync_service.dart';
import 'package:soplay/features/anilist/data/anilist_link_store.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/mal/data/mal_link_store.dart';
import 'package:soplay/features/mal/data/mal_service.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource _remoteDataSource;
  final HiveService _hiveService;

  AuthRepositoryImpl(this._remoteDataSource, this._hiveService);

  @override
  Future<Result<AuthToken>> login(String identifier, String password) async {
    try {
      final model = await _remoteDataSource.login(identifier, password);
      if (model.accessToken.isEmpty) {
        return Failure(Exception('Access token topilmadi'));
      }
      await _hiveService.saveAuth(
        accessToken: model.accessToken,
        refreshToken: model.refreshToken,
        user: model.user as UserModel,
      );
      return Success(model);
    } on DioException catch (e) {
      return Failure(Exception(_messageFrom(e)));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<AuthToken>> loginWithGoogle(String idToken) async {
    try {
      final model = await _remoteDataSource.loginWithGoogle(idToken);
      if (model.accessToken.isEmpty) {
        return Failure(Exception('Access token topilmadi'));
      }
      await _hiveService.saveAuth(
        accessToken: model.accessToken,
        refreshToken: model.refreshToken,
        user: model.user as UserModel,
      );
      return Success(model);
    } on DioException catch (e) {
      return Failure(Exception(_messageFrom(e)));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<void>> requestRegisterOtp({
    required String email,
    required String username,
    required String password,
  }) async {
    try {
      await _remoteDataSource.requestRegisterOtp(
        email: email,
        username: username,
        password: password,
      );
      return const Success(null);
    } on DioException catch (e) {
      return Failure(Exception(_messageFrom(e)));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<void>> resendRegisterOtp(String email) async {
    try {
      await _remoteDataSource.resendRegisterOtp(email);
      return const Success(null);
    } on DioException catch (e) {
      return Failure(Exception(_messageFrom(e)));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<AuthToken>> verifyRegisterOtp({
    required String email,
    required String code,
  }) async {
    try {
      final model = await _remoteDataSource.verifyRegisterOtp(
        email: email,
        code: code,
      );
      if (model.accessToken.isEmpty) {
        return Failure(Exception('Access token topilmadi'));
      }
      await _hiveService.saveAuth(
        accessToken: model.accessToken,
        refreshToken: model.refreshToken,
        user: model.user as UserModel,
      );
      return Success(model);
    } on DioException catch (e) {
      return Failure(Exception(_messageFrom(e)));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<void>> requestPasswordReset(String email) async {
    try {
      await _remoteDataSource.requestPasswordReset(email);
      return const Success(null);
    } on DioException catch (e) {
      return Failure(Exception(_messageFrom(e)));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<AuthToken>> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    try {
      final model = await _remoteDataSource.resetPassword(
        email: email,
        code: code,
        newPassword: newPassword,
      );
      if (model.accessToken.isEmpty) {
        return Failure(Exception('Access token topilmadi'));
      }
      // Stored exactly like a verified registration: the reset issues a real
      // session, and not saving it would leave the user staring at a login
      // screen straight after proving who they are.
      await _hiveService.saveAuth(
        accessToken: model.accessToken,
        refreshToken: model.refreshToken,
        user: model.user as UserModel,
      );
      return Success(model);
    } on DioException catch (e) {
      return Failure(Exception(_messageFrom(e)));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<UserEntity>> getProfile() async {
    try {
      final user = await _remoteDataSource.getProfile();
      await _hiveService.saveUser(user);
      return Success(user);
    } on DioException catch (e) {
      return Failure(Exception(_messageFrom(e)));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<UserEntity>> updateProfile({
    String? username,
    String? displayName,
    String? photoUrl,
  }) async {
    try {
      final user = await _remoteDataSource.updateProfile(
        username: username,
        displayName: displayName,
        photoUrl: photoUrl,
      );
      // Cached straight away: the profile screen reads the stored user, and
      // leaving the old copy there would show the previous name until the next
      // sign-in.
      await _hiveService.saveUser(user);
      return Success(user);
    } on DioException catch (e) {
      return Failure(Exception(_messageFrom(e)));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<String>> uploadAvatar(File file) async {
    try {
      final contentType = _contentTypeFor(file.path);
      if (contentType == null) {
        return Failure(Exception('auth.avatar_bad_format'.tr()));
      }
      final slot = await _remoteDataSource.avatarUploadUrl(contentType);

      // A bare client on purpose: the presigned url already carries its own
      // authorisation, and this app's bearer token has no business reaching
      // Cloudflare.
      await Dio().put<void>(
        slot.uploadUrl,
        data: file.openRead(),
        options: Options(
          headers: {
            Headers.contentTypeHeader: contentType,
            Headers.contentLengthHeader: await file.length(),
          },
        ),
      );
      return Success(slot.publicUrl);
    } on DioException catch (e) {
      return Failure(Exception(_messageFrom(e)));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  static String? _contentTypeFor(String path) {
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => null,
    };
  }

  @override
  Future<void> logout() async {
    try {
      await _remoteDataSource.logout();
    } on DioException {
      await _clearAccountScopedData();
      return;
    }
    await _clearAccountScopedData();
  }

  /// Tokens are not the only account-scoped state on the device.
  ///
  /// The watch-history sync cursor points at one account's rows; left behind,
  /// the next sign-in resumes from a stranger's position and uploads this
  /// person's viewing into their history.
  ///
  /// A tracker link is account-scoped for the same reason, and worse: its token
  /// writes to a real third-party list, so a leftover one would file the next
  /// person's viewing under a stranger's AniList or MyAnimeList profile.
  Future<void> _clearAccountScopedData() async {
    await _hiveService.clearAuth();
    if (getIt.isRegistered<HistorySyncService>()) {
      // The rows as well as the cursor. Clearing only the cursor left the
      // previous account's watch history on screen after they signed out —
      // Continue Watching, the History page and the counts in Profile all
      // still listed it, which is the account's data outliving the account.
      await getIt<HistorySyncService>().forgetAfterSignOut();
    }
    if (getIt.isRegistered<AnilistService>()) {
      await getIt<AnilistService>().forgetLocal();
    }
    if (getIt.isRegistered<AnilistLinkStore>()) {
      await getIt<AnilistLinkStore>().clear();
    }
    if (getIt.isRegistered<MalService>()) {
      await getIt<MalService>().forgetLocal();
    }
    if (getIt.isRegistered<MalLinkStore>()) {
      await getIt<MalLinkStore>().clear();
    }

    // Everything else the account put on this device.
    //
    // All of it is server-backed and comes back on the next sign-in: My List is
    // re-upserted from the server, the streak is refetched, and the statistics
    // are rebuilt from the account's own history. Leaving any of it behind
    // means somebody signs out, hands over the phone, and the next person opens
    // the app to another person's saved titles, streak and viewing totals.
    if (getIt.isRegistered<MyListLocalDataSource>()) {
      await getIt<MyListLocalDataSource>().clearLocalOnly();
    }
    if (getIt.isRegistered<StreakService>()) {
      getIt<StreakService>().reset();
    }
    // Not server-backed, and cleared for exactly that reason: nothing would
    // ever remove it otherwise, and a watch-time total is as personal as the
    // history it was counted from.
    await WatchStatsStore().clear();
  }

  String _messageFrom(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final msg = data['message'];
      if (msg is String && msg.isNotEmpty) return msg;
      if (msg is List && msg.isNotEmpty) return msg.first.toString();
    }
    return e.message ?? 'Xatolik yuz berdi';
  }
}
