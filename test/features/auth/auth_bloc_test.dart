import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/auth/data/services/google_auth_service.dart';
import 'package:soplay/features/auth/domain/entities/auth_token.dart';
import 'package:soplay/features/auth/domain/entities/user_entity.dart';
import 'package:soplay/features/auth/domain/repositories/auth_repository.dart';
import 'package:soplay/features/auth/domain/usecases/forgot_password_usecase.dart';
import 'package:soplay/features/auth/domain/usecases/google_login_usecase.dart';
import 'package:soplay/features/auth/domain/usecases/login_usecase.dart';
import 'package:soplay/features/auth/domain/usecases/register_usecase.dart';
import 'package:soplay/features/auth/domain/usecases/resend_otp_usecase.dart';
import 'package:soplay/features/auth/domain/usecases/verify_otp_usecase.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_event.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_state.dart';
import 'package:soplay/features/my_list/domain/usecases/sync_favorites_usecase.dart';
import 'package:soplay/features/notifications/data/services/notification_service.dart';

class _FakeLoginUseCase implements LoginUseCase {
  Result<AuthToken> result = Failure(Exception('unconfigured'));

  @override
  Future<Result<AuthToken>> call(String identifier, String password) async =>
      result;
}

class _FakeRegisterUseCase implements RegisterUseCase {
  Result<void> result = const Success(null);

  @override
  Future<Result<void>> call({
    required String email,
    required String username,
    required String password,
  }) async => result;
}

class _FakeVerifyOtpUseCase implements VerifyOtpUseCase {
  Result<AuthToken> result = Failure(Exception('unconfigured'));

  @override
  Future<Result<AuthToken>> call({
    required String email,
    required String code,
  }) async => result;
}

class _FakeResendOtpUseCase implements ResendOtpUseCase {
  Result<void> result = const Success(null);

  @override
  Future<Result<void>> call(String email) async => result;
}

class _FakeGoogleLoginUseCase implements GoogleLoginUseCase {
  @override
  Future<Result<AuthToken>> call(String idToken) async =>
      Failure(Exception('unsupported'));
}

class _FakeGoogleAuthService implements GoogleAuthService {
  @override
  Future<Result<String?>> signIn() async => const Success(null);

  @override
  Future<void> signOut() async {}
}

class _FakeRequestPasswordResetUseCase
    implements RequestPasswordResetUseCase {
  @override
  Future<Result<void>> call(String email) async => const Success(null);
}

class _FakeResetPasswordUseCase implements ResetPasswordUseCase {
  @override
  Future<Result<AuthToken>> call({
    required String email,
    required String otp,
    required String newPassword,
  }) async => Failure(Exception('unsupported'));
}

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<Result<UserEntity>> getProfile() async =>
      Failure(Exception('unsupported'));

  @override
  Future<Result<UserEntity>> updateProfile({String? username, File? avatar}) async =>
      Failure(Exception('unsupported'));

  @override
  Future<Result<AuthToken>> login(String identifier, String password) async =>
      Failure(Exception('unsupported'));

  @override
  Future<Result<AuthToken>> loginWithGoogle(String idToken) async =>
      Failure(Exception('unsupported'));

  @override
  Future<Result<void>> register({
    required String email,
    required String username,
    required String password,
  }) async => const Success(null);

  @override
  Future<Result<void>> resendOtp(String email) async => const Success(null);

  @override
  Future<Result<AuthToken>> verifyOtp({
    required String email,
    required String code,
  }) async => Failure(Exception('unsupported'));

  @override
  Future<Result<void>> requestPasswordReset(String email) async =>
      const Success(null);

  @override
  Future<Result<AuthToken>> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async => Failure(Exception('unsupported'));
}

class _FakeNotificationService implements NotificationService {
  @override
  Future<void> setup() async {}

  @override
  Future<void> unregister() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSyncFavoritesUseCase implements SyncFavoritesUseCase {
  @override
  Future<void> call() async {}
}

void main() {
  late Directory tempDir;
  late HiveService hiveService;
  late _FakeLoginUseCase fakeLogin;
  late _FakeRegisterUseCase fakeRegister;
  late _FakeVerifyOtpUseCase fakeVerifyOtp;
  late _FakeResendOtpUseCase fakeResendOtp;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('kaizoku_auth_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(AppConstants.authBox);
    await Hive.openBox(AppConstants.settingsBox);
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    final box = Hive.box(AppConstants.authBox);
    await box.clear();

    hiveService = HiveService();
    fakeLogin = _FakeLoginUseCase();
    fakeRegister = _FakeRegisterUseCase();
    fakeVerifyOtp = _FakeVerifyOtpUseCase();
    fakeResendOtp = _FakeResendOtpUseCase();
  });

  AuthBloc createBloc() {
    return AuthBloc(
      loginUseCase: fakeLogin,
      googleLoginUseCase: _FakeGoogleLoginUseCase(),
      googleAuthService: _FakeGoogleAuthService(),
      registerUseCase: fakeRegister,
      verifyOtpUseCase: fakeVerifyOtp,
      resendOtpUseCase: fakeResendOtp,
      requestPasswordResetUseCase: _FakeRequestPasswordResetUseCase(),
      resetPasswordUseCase: _FakeResetPasswordUseCase(),
      authRepository: _FakeAuthRepository(),
      hiveService: hiveService,
      notificationService: _FakeNotificationService(),
      syncFavorites: _FakeSyncFavoritesUseCase(),
    );
  }

  const dummyUser = UserEntity(
    id: 'user_123',
    email: 'test@kaizoku.app',
    username: 'kaizoku_user',
    avatar: null,
  );

  const dummyToken = AuthToken(
    accessToken: 'access_jwt_xyz',
    refreshToken: 'refresh_jwt_abc',
    user: dummyUser,
  );

  test('emits AuthInitial when no user credentials stored in Hive', () async {
    final bloc = createBloc();
    await expectLater(bloc.stream, emits(isA<AuthInitial>()));
    await bloc.close();
  });

  test('successful login emits AuthLoading then AuthLoaded', () async {
    fakeLogin.result = const Success(dummyToken);
    final bloc = createBloc();

    // First event is auto-added AuthStarted
    await expectLater(bloc.stream, emits(isA<AuthInitial>()));

    bloc.add(const AuthLoginRequested(
      identifier: 'test@kaizoku.app',
      password: 'secret_password',
    ));

    await expectLater(
      bloc.stream,
      emitsInOrder([
        isA<AuthLoading>(),
        predicate<AuthState>((s) =>
            s is AuthLoaded && s.token.accessToken == 'access_jwt_xyz' &&
            s.token.user.username == 'kaizoku_user'),
      ]),
    );

    await bloc.close();
  });

  test('failed login emits AuthLoading then AuthError', () async {
    fakeLogin.result = Failure(Exception('Invalid credentials'));
    final bloc = createBloc();

    await expectLater(bloc.stream, emits(isA<AuthInitial>()));

    bloc.add(const AuthLoginRequested(
      identifier: 'test@kaizoku.app',
      password: 'wrong_password',
    ));

    await expectLater(
      bloc.stream,
      emitsInOrder([
        isA<AuthLoading>(),
        predicate<AuthState>((s) => s is AuthError && s.message.isNotEmpty),
      ]),
    );

    await bloc.close();
  });

  test('registration request emits AuthOtpPending on success', () async {
    fakeRegister.result = const Success(null);
    final bloc = createBloc();

    await expectLater(bloc.stream, emits(isA<AuthInitial>()));

    bloc.add(const AuthRegisterRequested(
      email: 'new@kaizoku.app',
      username: 'new_user',
      password: 'password123',
    ));

    await expectLater(
      bloc.stream,
      emitsInOrder([
        isA<AuthLoading>(),
        predicate<AuthState>((s) =>
            s is AuthOtpPending && s.email == 'new@kaizoku.app'),
      ]),
    );

    await bloc.close();
  });

  test('OTP verification emits AuthLoaded on valid OTP', () async {
    fakeRegister.result = const Success(null);
    fakeVerifyOtp.result = const Success(dummyToken);
    final bloc = createBloc();

    await expectLater(bloc.stream, emits(isA<AuthInitial>()));

    bloc.add(const AuthRegisterRequested(
      email: 'new@kaizoku.app',
      username: 'new_user',
      password: 'password123',
    ));

    await expectLater(
      bloc.stream,
      emitsInOrder([
        isA<AuthLoading>(),
        isA<AuthOtpPending>(),
      ]),
    );

    bloc.add(const AuthOtpVerifyRequested('123456'));

    await expectLater(
      bloc.stream,
      emitsInOrder([
        isA<AuthLoading>(),
        predicate<AuthState>((s) => s is AuthLoaded && s.token == dummyToken),
      ]),
    );

    await bloc.close();
  });

  test('AuthSessionExpired clears auth cache and resets to AuthInitial', () async {
    await hiveService.saveToken(dummyToken);
    final bloc = createBloc();

    await expectLater(
      bloc.stream,
      emits(predicate<AuthState>((s) => s is AuthLoaded)),
    );

    bloc.add(const AuthSessionExpired());

    await expectLater(
      bloc.stream,
      emits(isA<AuthInitial>()),
    );

    expect(hiveService.getToken(), isNull);
    await bloc.close();
  });
}
