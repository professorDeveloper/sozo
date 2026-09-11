import 'package:soplay/features/app_lock/domain/entities/pin_check.dart';

abstract class AppLockRepository {
  bool get isEnabled;
  int get pinLength;
  bool get isBiometricPreferred;

  Future<void> setPin(String pin);
  Future<PinCheckResult> checkPin(String pin);
  Future<DateTime?> lockedOutUntil();
  Future<bool> isPinReadable();
  Future<void> disable();
  Future<void> ensureConsistent();

  /// The "forgot PIN" way out: wipes what the lock protected (the private
  /// list), then switches the lock off. Never just the second half — a reset
  /// that kept the private list would be a way around the PIN.
  Future<void> resetForgotten();

  Future<bool> isBiometricAvailable();
  Future<void> setBiometricPreferred(bool value);
  Future<bool> authenticateWithBiometrics(String reason);
}
