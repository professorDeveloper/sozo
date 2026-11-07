import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/app_lock/data/pin_secrets.dart';
import 'package:soplay/features/app_lock/domain/entities/pin_check.dart';

class AppLockLocalDataSource {
  AppLockLocalDataSource({
    required HiveService hiveService,
    FlutterSecureStorage? secureStorage,
    LocalAuthentication? localAuth,
    DeviceBiometrics? biometrics,
    DateTime Function()? clock,
  }) : _hive = hiveService,
       _secure =
           secureStorage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(encryptedSharedPreferences: true),
             iOptions: IOSOptions(
               accessibility: KeychainAccessibility.first_unlock,
             ),
           ),
       _biometrics = biometrics ?? DeviceBiometrics(localAuth),
       _now = clock ?? DateTime.now;

  final HiveService _hive;
  final FlutterSecureStorage _secure;
  final DeviceBiometrics _biometrics;
  final DateTime Function() _now;

  static const String _failuresKey = 'app_lock_failures';
  static const String _lockedUntilKey = 'app_lock_locked_until';

  bool get isEnabled => _hive.isAppLockEnabled;
  int get pinLength => _hive.appLockPinLength;
  bool get isBiometricPreferred => _hive.isAppLockBiometricEnabled;

  Future<void> setPin(String pin) async {
    final salt = PinHash.newSalt();
    final hash = await PinHash.hash(pin, salt);
    await _secure.write(key: AppConstants.appLockPinSaltSecureKey, value: salt);
    await _secure.write(key: AppConstants.appLockPinHashSecureKey, value: hash);
    await _clearFailures();
    await _hive.setAppLockEnabled(true);
    await _hive.setAppLockPinLength(pin.length);
  }

  /// Checks [pin], counting wrong guesses and imposing a growing wait.
  ///
  /// Never switches the lock off on its own. The old version disabled the lock
  /// whenever the stored PIN could not be read — so anything that made the
  /// keystore unreadable (a restore onto a new phone, a keystore reset, a
  /// flaky read) opened the app, and the private list, to whoever held it.
  /// That case is now [PinCheck.unavailable], and the only way past it is the
  /// explicit reset, which wipes what the lock was protecting.
  Future<PinCheckResult> checkPin(String pin) async {
    final until = await lockedOutUntil();
    if (until != null) return PinCheckResult.lockedOut(until);

    final String? salt;
    final String? stored;
    try {
      salt = await _secure.read(key: AppConstants.appLockPinSaltSecureKey);
      stored = await _secure.read(key: AppConstants.appLockPinHashSecureKey);
    } catch (_) {
      return const PinCheckResult.unavailable();
    }
    if (salt == null || stored == null) {
      return const PinCheckResult.unavailable();
    }

    final bool ok;
    if (PinHash.isPbkdf2(stored)) {
      ok = await PinHash.verify(pin, salt, stored);
    } else {
      ok = PinHash.constantTimeEquals(_legacyHash(pin, salt), stored);
      // Upgrade in place, now that the PIN is in hand to re-hash.
      if (ok) {
        try {
          final upgraded = await PinHash.hash(pin, salt);
          await _secure.write(
            key: AppConstants.appLockPinHashSecureKey,
            value: upgraded,
          );
        } catch (_) {}
      }
    }

    if (ok) {
      await _clearFailures();
      return const PinCheckResult.ok();
    }
    return _recordFailure();
  }

  /// When the next guess is allowed, or null if it is allowed now.
  Future<DateTime?> lockedOutUntil() async {
    try {
      final raw = await _secure.read(key: _lockedUntilKey);
      final ms = int.tryParse(raw ?? '');
      if (ms == null) return null;
      final until = DateTime.fromMillisecondsSinceEpoch(ms);
      return until.isAfter(_now()) ? until : null;
    } catch (_) {
      return null;
    }
  }

  /// Whether a PIN can actually be checked: the lock is on and its secret is
  /// readable. False with the lock on means the lock screen must offer the
  /// reset path, because no PIN will ever be accepted.
  Future<bool> isPinReadable() async {
    try {
      final salt = await _secure.read(
        key: AppConstants.appLockPinSaltSecureKey,
      );
      final hash = await _secure.read(
        key: AppConstants.appLockPinHashSecureKey,
      );
      return salt != null && hash != null;
    } catch (_) {
      return false;
    }
  }

  /// Kept for callers that ran it at startup. It no longer turns the lock
  /// off — see [checkPin] — and only drops a lockout that has already ended.
  Future<void> ensureConsistent() async {
    if (!_hive.isAppLockEnabled) return;
    await lockedOutUntil();
  }

  Future<void> disable() async {
    await _secure.delete(key: AppConstants.appLockPinHashSecureKey);
    await _secure.delete(key: AppConstants.appLockPinSaltSecureKey);
    await _clearFailures();
    await _hive.setAppLockEnabled(false);
    await _hive.setAppLockBiometricEnabled(false);
  }

  Future<void> setBiometricPreferred(bool value) =>
      _hive.setAppLockBiometricEnabled(value);

  Future<bool> isBiometricAvailable() => _biometrics.isAvailable();

  Future<bool> authenticateWithBiometrics(String reason) async {
    final ok = await _biometrics.authenticate(reason);
    if (ok) await _clearFailures();
    return ok;
  }

  Future<PinCheckResult> _recordFailure() async {
    var failures = 0;
    try {
      failures = int.tryParse(await _secure.read(key: _failuresKey) ?? '') ?? 0;
    } catch (_) {}
    failures++;
    try {
      await _secure.write(key: _failuresKey, value: '$failures');
    } catch (_) {}
    final result = PinBackoff.afterFailure(failures, _now());
    final until = result.retryAt;
    if (until == null) return result;
    try {
      await _secure.write(
        key: _lockedUntilKey,
        value: '${until.millisecondsSinceEpoch}',
      );
    } catch (_) {}
    return result;
  }

  Future<void> _clearFailures() async {
    try {
      await _secure.delete(key: _failuresKey);
      await _secure.delete(key: _lockedUntilKey);
    } catch (_) {}
  }

  /// The original single-round hash. Kept only to recognise PINs set before
  /// PBKDF2, which [checkPin] upgrades on their next unlock. The `soplay`
  /// suffix is part of those stored hashes — changing it would lock every
  /// such user out, so it must stay exactly as it is.
  static String _legacyHash(String pin, String salt) {
    final bytes = utf8.encode('$salt::$pin::soplay');
    return sha256.convert(bytes).toString();
  }
}
