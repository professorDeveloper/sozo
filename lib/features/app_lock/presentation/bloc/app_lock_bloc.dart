import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/features/app_lock/domain/entities/pin_check.dart';
import 'package:soplay/features/app_lock/domain/repositories/app_lock_repository.dart';

import 'app_lock_event.dart';
import 'app_lock_state.dart';

enum AppLockMode { setup, verify, change }

class AppLockBloc extends Bloc<AppLockEvent, AppLockState> {
  AppLockBloc({required AppLockRepository repository, required this.mode})
    : _repo = repository,
      super(_initialFor(repository, mode)) {
    on<AppLockStarted>(_onStarted);
    on<AppLockPinLengthChosen>(_onLengthChosen);
    on<AppLockPinDigitPressed>(_onDigit);
    on<AppLockPinBackspacePressed>(_onBackspace);
    on<AppLockResetEntry>(_onReset);
    on<AppLockBiometricRequested>(_onBiometric);
    on<AppLockToggleBiometric>(_onToggleBiometric);
    on<AppLockDisableRequested>(_onDisable);
    on<AppLockLockoutEnded>(_onLockoutEnded);
    on<AppLockResetRequested>(_onResetRequested);
  }

  final AppLockRepository _repo;
  final AppLockMode mode;
  Timer? _lockoutTimer;

  static AppLockState _initialFor(AppLockRepository repo, AppLockMode mode) {
    final base = AppLockState.initial().copyWith(
      pinLength: repo.pinLength,
      biometricPreferred: repo.isBiometricPreferred,
    );
    switch (mode) {
      case AppLockMode.setup:
        return base.copyWith(stage: AppLockStage.chooseLength);
      case AppLockMode.verify:
        return base.copyWith(stage: AppLockStage.verify);
      case AppLockMode.change:
        return base.copyWith(stage: AppLockStage.verify);
    }
  }

  Future<void> _onStarted(
    AppLockStarted event,
    Emitter<AppLockState> emit,
  ) async {
    final available = await _repo.isBiometricAvailable();
    emit(state.copyWith(biometricAvailable: available));
    if (mode == AppLockMode.setup) return;
    // A lockout outlives the screen — leaving and coming back must not reset
    // the wait.
    final until = await _repo.lockedOutUntil();
    if (until != null) _enterLockout(until, emit);
    if (_repo.isEnabled && !await _repo.isPinReadable()) {
      emit(
        state.copyWith(
          pinUnavailable: true,
          errorTick: state.errorTick + 1,
          errorMessage: 'app_lock.pin_unavailable',
        ),
      );
    }
  }

  void _enterLockout(DateTime until, Emitter<AppLockState> emit) {
    final seconds = until.difference(DateTime.now()).inSeconds + 1;
    emit(
      state.copyWith(
        entered: '',
        isProcessing: false,
        retryAt: until,
        errorTick: state.errorTick + 1,
        errorMessage: 'app_lock.locked_out',
        errorArgs: ['$seconds'],
      ),
    );
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer(
      until.difference(DateTime.now()),
      () => add(const AppLockLockoutEnded()),
    );
  }

  void _onLockoutEnded(AppLockLockoutEnded event, Emitter<AppLockState> emit) {
    emit(state.copyWith(clearRetryAt: true, clearError: true));
  }

  Future<void> _onResetRequested(
    AppLockResetRequested event,
    Emitter<AppLockState> emit,
  ) async {
    emit(state.copyWith(isProcessing: true));
    await _repo.resetForgotten();
    emit(
      state.copyWith(
        stage: AppLockStage.done,
        entered: '',
        isProcessing: false,
        pinUnavailable: false,
        clearRetryAt: true,
        clearError: true,
      ),
    );
  }

  @override
  Future<void> close() {
    _lockoutTimer?.cancel();
    return super.close();
  }

  void _onLengthChosen(
    AppLockPinLengthChosen event,
    Emitter<AppLockState> emit,
  ) {
    emit(
      state.copyWith(
        pinLength: event.length,
        stage: AppLockStage.enterNew,
        entered: '',
        firstPin: '',
        clearError: true,
      ),
    );
  }

  Future<void> _onDigit(
    AppLockPinDigitPressed event,
    Emitter<AppLockState> emit,
  ) async {
    if (state.isProcessing || state.isLockedOut || state.pinUnavailable) return;
    if (state.entered.length >= state.pinLength) return;
    final next = state.entered + event.digit;
    emit(state.copyWith(entered: next, clearError: true));
    if (next.length == state.pinLength) {
      await _handleFullEntry(emit);
    }
  }

  void _onBackspace(
    AppLockPinBackspacePressed event,
    Emitter<AppLockState> emit,
  ) {
    if (state.entered.isEmpty) return;
    emit(
      state.copyWith(
        entered: state.entered.substring(0, state.entered.length - 1),
        clearError: true,
      ),
    );
  }

  void _onReset(AppLockResetEntry event, Emitter<AppLockState> emit) {
    emit(state.copyWith(entered: '', clearError: true));
  }

  Future<void> _handleFullEntry(Emitter<AppLockState> emit) async {
    switch (state.stage) {
      case AppLockStage.enterNew:
        emit(
          state.copyWith(
            firstPin: state.entered,
            entered: '',
            stage: AppLockStage.confirmNew,
          ),
        );
      case AppLockStage.confirmNew:
        if (state.entered == state.firstPin) {
          emit(state.copyWith(isProcessing: true));
          await _repo.setPin(state.entered);
          emit(
            state.copyWith(
              stage: AppLockStage.done,
              isProcessing: false,
              entered: '',
              firstPin: '',
            ),
          );
        } else {
          emit(
            state.copyWith(
              stage: AppLockStage.enterNew,
              entered: '',
              firstPin: '',
              errorTick: state.errorTick + 1,
              errorMessage: 'app_lock.pin_mismatch',
            ),
          );
        }
      case AppLockStage.verify:
        emit(state.copyWith(isProcessing: true));
        final result = await _repo.checkPin(state.entered);
        if (result.isOk) {
          if (mode == AppLockMode.change) {
            emit(
              state.copyWith(
                stage: AppLockStage.chooseLength,
                entered: '',
                firstPin: '',
                isProcessing: false,
                clearError: true,
              ),
            );
          } else {
            emit(
              state.copyWith(
                stage: AppLockStage.done,
                entered: '',
                isProcessing: false,
                clearError: true,
              ),
            );
          }
        } else {
          switch (result.outcome) {
            case PinCheck.lockedOut:
              _enterLockout(result.retryAt!, emit);
            case PinCheck.unavailable:
              emit(
                state.copyWith(
                  entered: '',
                  isProcessing: false,
                  pinUnavailable: true,
                  errorTick: state.errorTick + 1,
                  errorMessage: 'app_lock.pin_unavailable',
                ),
              );
            case PinCheck.wrong:
            case PinCheck.ok:
              emit(
                state.copyWith(
                  entered: '',
                  isProcessing: false,
                  errorTick: state.errorTick + 1,
                  errorMessage: 'app_lock.pin_wrong',
                ),
              );
          }
        }
      case AppLockStage.chooseLength:
      case AppLockStage.done:
      case AppLockStage.disabled:
        break;
    }
  }

  Future<void> _onBiometric(
    AppLockBiometricRequested event,
    Emitter<AppLockState> emit,
  ) async {
    if (!state.biometricAvailable) return;
    final ok = await _repo.authenticateWithBiometrics(event.reason);
    if (ok) {
      emit(state.copyWith(stage: AppLockStage.done, clearError: true));
    }
  }

  Future<void> _onToggleBiometric(
    AppLockToggleBiometric event,
    Emitter<AppLockState> emit,
  ) async {
    if (event.enabled) {
      final available = await _repo.isBiometricAvailable();
      if (!available) {
        emit(
          state.copyWith(
            errorTick: state.errorTick + 1,
            errorMessage: 'app_lock.biometric_unavailable',
          ),
        );
        return;
      }
      final authed = await _repo.authenticateWithBiometrics(
        'app_lock.biometric_enable_reason',
      );
      if (!authed) return;
    }
    await _repo.setBiometricPreferred(event.enabled);
    emit(state.copyWith(biometricPreferred: event.enabled));
  }

  Future<void> _onDisable(
    AppLockDisableRequested event,
    Emitter<AppLockState> emit,
  ) async {
    await _repo.disable();
    emit(
      state.copyWith(
        stage: AppLockStage.disabled,
        entered: '',
        firstPin: '',
        biometricPreferred: false,
        clearError: true,
      ),
    );
  }
}
