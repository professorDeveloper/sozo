import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/auth/domain/entities/auth_token.dart';
import 'package:soplay/features/auth/domain/repositories/auth_repository.dart';
import 'package:soplay/features/auth/data/services/google_auth_service.dart';
import 'package:soplay/features/auth/domain/usecases/forgot_password_usecase.dart';
import 'package:soplay/features/auth/domain/usecases/google_login_usecase.dart';
import 'package:soplay/features/auth/domain/usecases/login_usecase.dart';
import 'package:soplay/features/auth/domain/usecases/register_usecase.dart';
import 'package:soplay/features/auth/domain/usecases/resend_otp_usecase.dart';
import 'package:soplay/features/auth/domain/usecases/verify_otp_usecase.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_state.dart';
import 'package:soplay/features/my_list/domain/usecases/sync_favorites_usecase.dart';
import 'package:soplay/features/notifications/data/services/notification_service.dart';

import 'auth_event.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/features/history/data/history_sync_service.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final LoginUseCase loginUseCase;
  final GoogleLoginUseCase googleLoginUseCase;
  final GoogleAuthService googleAuthService;
  final RegisterUseCase registerUseCase;
  final VerifyOtpUseCase verifyOtpUseCase;
  final ResendOtpUseCase resendOtpUseCase;
  final RequestPasswordResetUseCase requestPasswordResetUseCase;
  final ResetPasswordUseCase resetPasswordUseCase;
  final AuthRepository authRepository;
  final HiveService hiveService;
  final NotificationService notificationService;
  final SyncFavoritesUseCase syncFavorites;

  static const Duration _resendCooldown = Duration(seconds: 60);

  AuthBloc({
    required this.loginUseCase,
    required this.googleLoginUseCase,
    required this.googleAuthService,
    required this.registerUseCase,
    required this.verifyOtpUseCase,
    required this.resendOtpUseCase,
    required this.requestPasswordResetUseCase,
    required this.resetPasswordUseCase,
    required this.authRepository,
    required this.hiveService,
    required this.notificationService,
    required this.syncFavorites,
  }) : super(AuthInitial()) {
    on<AuthStarted>(_onStarted);
    on<AuthLoginRequested>(_onLogin);
    on<AuthGoogleRequested>(_onGoogleLogin);
    on<AuthRegisterRequested>(_onRegister);
    on<AuthOtpVerifyRequested>(_onVerifyOtp);
    on<AuthOtpResendRequested>(_onResendOtp);
    on<AuthOtpReset>((_, emit) => emit(AuthInitial()));
    on<AuthPasswordResetRequested>(_onPasswordResetRequested);
    on<AuthPasswordResetSubmitted>(_onPasswordResetSubmitted);
    on<AuthLogoutRequested>(_onLogout);
    on<AuthSessionExpired>(_onSessionExpired);
    on<AuthProfileRefreshRequested>(_onProfileRefresh);
    add(const AuthStarted());
  }

  Future<void> _onSessionExpired(
    AuthSessionExpired event,
    Emitter<AuthState> emit,
  ) async {
    if (state is AuthInitial) return;
    await notificationService.unregister();
    await googleAuthService.signOut();
    await hiveService.clearAuth();
    emit(AuthInitial());
  }

  Future<void> _onStarted(AuthStarted event, Emitter<AuthState> emit) async {
    final accessToken = hiveService.getToken();
    final user = hiveService.getUser();
    if (accessToken == null || accessToken.isEmpty || user == null) {
      emit(AuthInitial());
      return;
    }

    emit(
      AuthLoaded(
        token: AuthToken(
          accessToken: accessToken,
          refreshToken: hiveService.getRefreshToken() ?? '',
          user: user,
        ),
      ),
    );

    unawaited(syncFavorites());
    unawaited(_syncHistory());
    unawaited(notificationService.setup());
    add(const AuthProfileRefreshRequested());
  }

  Future<void> _onLogin(
    AuthLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    final result = await loginUseCase(event.identifier, event.password);
    switch (result) {
      case Success(:final value):
        emit(AuthLoaded(token: value));
        unawaited(syncFavorites());
        unawaited(_syncHistory());
        unawaited(notificationService.setup());
      case Failure(:final error):
        emit(AuthError(message: _friendlyError(error)));
    }
  }

  Future<void> _onGoogleLogin(
    AuthGoogleRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    final token = await googleAuthService.signIn();
    switch (token) {
      case Success(value: final idToken?):
        final result = await googleLoginUseCase(idToken);
        switch (result) {
          case Success(:final value):
            emit(AuthLoaded(token: value));
            unawaited(syncFavorites());
            unawaited(_syncHistory());
            unawaited(notificationService.setup());
          case Failure(:final error):
            // The Firebase session is live but Sozo's is not, so drop it —
            // otherwise the next attempt silently reuses the same account and
            // never reopens the picker.
            await googleAuthService.signOut();
            emit(AuthError(message: _friendlyError(error)));
        }
      case Success():
        // Backed out of the account picker. Not an error, so the screen goes
        // back to how it was rather than flashing a red snackbar.
        emit(AuthInitial());
      case Failure(:final error):
        emit(AuthError(message: _friendlyError(error)));
    }
  }

  Future<void> _onRegister(
    AuthRegisterRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    final result = await registerUseCase(
      email: event.email,
      username: event.username,
      password: event.password,
    );
    switch (result) {
      case Success():
        emit(
          AuthOtpPending(
            email: event.email,
            cooldownUntil: DateTime.now().add(_resendCooldown),
          ),
        );
      case Failure(:final error):
        emit(AuthError(message: _friendlyError(error)));
    }
  }

  Future<void> _onVerifyOtp(
    AuthOtpVerifyRequested event,
    Emitter<AuthState> emit,
  ) async {
    final current = state;
    if (current is AuthOtpPending) {
      emit(current.copyWith(verifying: true, clearError: true));
    }
    final result = await verifyOtpUseCase(email: event.email, code: event.code);
    // Re-read state after the await — a concurrent resend may have replaced the
    // pending state (cooldown/justResent) while verify was in flight.
    final pending = state;
    switch (result) {
      case Success(:final value):
        emit(AuthLoaded(token: value));
        unawaited(syncFavorites());
        unawaited(_syncHistory());
        unawaited(notificationService.setup());
      case Failure(:final error):
        final msg = _friendlyError(error);
        if (pending is AuthOtpPending) {
          emit(pending.copyWith(verifying: false, error: msg));
        } else {
          emit(AuthError(message: msg));
        }
    }
  }

  Future<void> _onPasswordResetRequested(
    AuthPasswordResetRequested event,
    Emitter<AuthState> emit,
  ) async {
    final current = state;
    if (event.isResend && current is AuthPasswordResetPending) {
      if (DateTime.now().isBefore(current.cooldownUntil)) return;
      emit(current.copyWith(resending: true, clearError: true));
    } else if (!event.isResend) {
      emit(AuthLoading());
    }

    final result = await requestPasswordResetUseCase(event.email);
    final pending = state;
    switch (result) {
      case Success():
        // The server answers the same way whether or not the address exists, so
        // this screen must too — telling the user "no such account" here is how
        // an app leaks which emails are registered.
        emit(
          pending is AuthPasswordResetPending
              ? pending.copyWith(
                  resending: false,
                  justSent: true,
                  cooldownUntil: DateTime.now().add(_resendCooldown),
                  clearError: true,
                )
              : AuthPasswordResetPending(
                  email: event.email,
                  cooldownUntil: DateTime.now().add(_resendCooldown),
                  justSent: true,
                ),
        );
      case Failure(:final error):
        final msg = _friendlyError(error);
        emit(
          pending is AuthPasswordResetPending
              ? pending.copyWith(resending: false, error: msg)
              : AuthError(message: msg),
        );
    }
  }

  Future<void> _onPasswordResetSubmitted(
    AuthPasswordResetSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    final current = state;
    if (current is AuthPasswordResetPending) {
      emit(current.copyWith(submitting: true, clearError: true));
    }

    final result = await resetPasswordUseCase(
      email: event.email,
      code: event.code,
      newPassword: event.newPassword,
    );
    // Re-read after the await, exactly as the register flow does: a resend may
    // have replaced the pending state while this was in flight.
    final pending = state;
    switch (result) {
      case Success(:final value):
        emit(AuthLoaded(token: value));
        unawaited(syncFavorites());
        unawaited(_syncHistory());
        unawaited(notificationService.setup());
      case Failure(:final error):
        final msg = _friendlyError(error);
        emit(
          pending is AuthPasswordResetPending
              ? pending.copyWith(submitting: false, error: msg)
              : AuthError(message: msg),
        );
    }
  }

  Future<void> _onResendOtp(
    AuthOtpResendRequested event,
    Emitter<AuthState> emit,
  ) async {
    final current = state;
    if (current is AuthOtpPending) {
      if (DateTime.now().isBefore(current.cooldownUntil)) return;
      emit(current.copyWith(resending: true, clearError: true));
    }
    final result = await resendOtpUseCase(event.email);
    // Re-read state after the await — a concurrent verify may have updated it.
    final pending = state;
    switch (result) {
      case Success():
        if (pending is AuthOtpPending) {
          emit(
            pending.copyWith(
              resending: false,
              justResent: true,
              cooldownUntil: DateTime.now().add(_resendCooldown),
            ),
          );
        } else {
          emit(
            AuthOtpPending(
              email: event.email,
              cooldownUntil: DateTime.now().add(_resendCooldown),
              justResent: true,
            ),
          );
        }
      case Failure(:final error):
        final msg = _friendlyError(error);
        if (pending is AuthOtpPending) {
          emit(pending.copyWith(resending: false, error: msg));
        } else {
          emit(AuthError(message: msg));
        }
    }
  }

  Future<void> _onLogout(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    await notificationService.unregister();
    await googleAuthService.signOut();
    await authRepository.logout();
    emit(AuthInitial());
  }

  Future<void> _onProfileRefresh(
    AuthProfileRefreshRequested event,
    Emitter<AuthState> emit,
  ) async {
    final current = state;
    final accessToken = hiveService.getToken();
    if (accessToken == null || accessToken.isEmpty) {
      if (current is AuthLoaded) emit(AuthInitial());
      return;
    }

    final result = await authRepository.getProfile();
    switch (result) {
      case Success(:final value):
        // Auth may have been cleared (logout) while getProfile was in flight —
        // don't re-emit a signed-in state with a blank token.
        if (hiveService.getToken()?.isNotEmpty != true) {
          emit(AuthInitial());
          return;
        }
        emit(
          AuthLoaded(
            token: AuthToken(
              accessToken: hiveService.getToken() ?? '',
              refreshToken: hiveService.getRefreshToken() ?? '',
              user: value,
            ),
          ),
        );
      case Failure():
        final stillAuthenticated = hiveService.getToken()?.isNotEmpty == true;
        if (!stillAuthenticated) {
          emit(AuthInitial());
          return;
        }
        if (current is AuthLoaded) return;
        final cachedUser = hiveService.getUser();
        if (cachedUser != null) {
          emit(
            AuthLoaded(
              token: AuthToken(
                accessToken: hiveService.getToken() ?? '',
                refreshToken: hiveService.getRefreshToken() ?? '',
                user: cachedUser,
              ),
            ),
          );
        }
    }
  }

  /// Pull the account's watch history on sign-in.
  ///
  /// Alongside syncFavorites rather than inside it: favorites are a curated
  /// list the user owns, history is written by the player, and the two fail
  /// independently. Registration is checked because the bloc is constructed in
  /// tests where the sync service is not wired.
  Future<void> _syncHistory() async {
    if (!getIt.isRegistered<HistorySyncService>()) return;
    // Before anything is uploaded: the rows sitting on this phone may belong to
    // whoever signed in last. Signing out resets the push watermark, so the
    // first sync pushes EVERYTHING local — which is what you want when the same
    // person returns, and a data leak when it is somebody else.
    final userId = hiveService.getUser()?.id;
    if (userId != null && userId.isNotEmpty) {
      await getIt<HistorySyncService>().adoptFor(userId);
    }
    await getIt<HistorySyncService>().sync();
    // The AniList link is stored on the account, so signing in on a new device
    // is exactly when it should reappear — without this, connecting on the
    // phone would leave every other device looking unconnected.
    if (getIt.isRegistered<AnilistService>()) {
      await getIt<AnilistService>().refreshFromAccount();
    }
  }

  String _friendlyError(Object error) {
    return error.toString().replaceFirst('Exception: ', '');
  }
}
