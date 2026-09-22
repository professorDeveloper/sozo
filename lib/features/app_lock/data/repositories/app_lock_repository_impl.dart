import 'package:soplay/features/app_lock/data/datasources/app_lock_local_data_source.dart';
import 'package:soplay/features/app_lock/domain/entities/pin_check.dart';
import 'package:soplay/features/app_lock/domain/repositories/app_lock_repository.dart';

class AppLockRepositoryImpl implements AppLockRepository {
  AppLockRepositoryImpl(this._source, {Future<void> Function()? wipeProtected})
    : _wipeProtected = wipeProtected;

  final AppLockLocalDataSource _source;
  final Future<void> Function()? _wipeProtected;

  @override
  bool get isEnabled => _source.isEnabled;

  @override
  int get pinLength => _source.pinLength;

  @override
  bool get isBiometricPreferred => _source.isBiometricPreferred;

  @override
  Future<void> setPin(String pin) => _source.setPin(pin);

  @override
  Future<PinCheckResult> checkPin(String pin) => _source.checkPin(pin);

  @override
  Future<DateTime?> lockedOutUntil() => _source.lockedOutUntil();

  @override
  Future<bool> isPinReadable() => _source.isPinReadable();

  @override
  Future<void> disable() => _source.disable();

  @override
  Future<void> ensureConsistent() => _source.ensureConsistent();

  @override
  Future<void> resetForgotten() async {
    await _wipeProtected?.call();
    await _source.disable();
  }

  @override
  Future<bool> isBiometricAvailable() => _source.isBiometricAvailable();

  @override
  Future<void> setBiometricPreferred(bool value) =>
      _source.setBiometricPreferred(value);

  @override
  Future<bool> authenticateWithBiometrics(String reason) =>
      _source.authenticateWithBiometrics(reason);
}
