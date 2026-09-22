import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/app_lock/domain/entities/pin_check.dart';

class AppLockLocalDataSource {
  AppLockLocalDataSource({
    required HiveService hiveService,
    FlutterSecureStorage? secureStorage,
    LocalAuthentication? localAuth,
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
       _localAuth = localAuth ?? LocalAuthentication(),
       _now = clock ?? DateTime.now;

  final HiveService _hive;
  final FlutterSecureStorage _secure;
  final LocalAuthentication _localAuth;
  final DateTime Function() _now;

  /// PBKDF2 rounds for a new hash. A PIN has at most a million values, so the
  /// hash is only ever a speed bump for someone holding a copy of the stored
  /// secret; the real protection is that the secret sits in the platform
  /// keystore and that guessing on the device is rate-limited below. The
  /// count is stored with the hash, so it can be raised later without
  /// invalidating anyone's PIN.
  static const int pbkdf2Iterations = 60000;

  /// Wrong guesses allowed before a wait is imposed.
  static const int freeAttempts = 5;

  /// The first wait; it doubles with each further wrong guess, up to [maxWait].
  static const Duration firstWait = Duration(seconds: 30);
  static const Duration maxWait = Duration(hours: 1);

  static const String _failuresKey = 'app_lock_failures';
  static const String _lockedUntilKey = 'app_lock_locked_until';

  bool get isEnabled => _hive.isAppLockEnabled;
  int get pinLength => _hive.appLockPinLength;
  bool get isBiometricPreferred => _hive.isAppLockBiometricEnabled;

  Future<void> setPin(String pin) async {
    final salt = _generateSalt();
    final hash = await _hashPbkdf2(pin, salt, pbkdf2Iterations);
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
    if (stored.startsWith('pbkdf2\$')) {
      ok = await _verifyPbkdf2(pin, salt, stored);
    } else {
      ok = _constantTimeEquals(_legacyHash(pin, salt), stored);
      // Upgrade in place, now that the PIN is in hand to re-hash.
      if (ok) {
        try {
          final upgraded = await _hashPbkdf2(pin, salt, pbkdf2Iterations);
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

  Future<bool> isBiometricAvailable() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      if (!supported) return false;
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!canCheck) return false;
      final available = await _localAuth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics(String reason) async {
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      if (ok) await _clearFailures();
      return ok;
    } catch (_) {
      return false;
    }
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
    final wait = waitAfter(failures);
    if (wait == null) {
      return PinCheckResult.wrong(freeAttempts - failures);
    }
    final until = _now().add(wait);
    try {
      await _secure.write(
        key: _lockedUntilKey,
        value: '${until.millisecondsSinceEpoch}',
      );
    } catch (_) {}
    return PinCheckResult.lockedOut(until);
  }

  /// The wait imposed after the [failures]-th wrong guess in a row, or null
  /// while guesses are still free.
  static Duration? waitAfter(int failures) {
    if (failures < freeAttempts) return null;
    final doublings = min(failures - freeAttempts, 20);
    final wait = firstWait * pow(2, doublings).toInt();
    return wait > maxWait ? maxWait : wait;
  }

  Future<void> _clearFailures() async {
    try {
      await _secure.delete(key: _failuresKey);
      await _secure.delete(key: _lockedUntilKey);
    } catch (_) {}
  }

  String _generateSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// The original single-round hash. Kept only to recognise PINs set before
  /// PBKDF2, which [checkPin] upgrades on their next unlock. The `soplay`
  /// suffix is part of those stored hashes — changing it would lock every
  /// such user out, so it must stay exactly as it is.
  static String _legacyHash(String pin, String salt) {
    final bytes = utf8.encode('$salt::$pin::soplay');
    return sha256.convert(bytes).toString();
  }

  Future<bool> _verifyPbkdf2(String pin, String salt, String stored) async {
    // pbkdf2$sha256$<iterations>$<base64 key>
    final parts = stored.split('\$');
    if (parts.length != 4 || parts[1] != 'sha256') return false;
    final iterations = int.tryParse(parts[2]);
    if (iterations == null || iterations <= 0) return false;
    final candidate = await _hashPbkdf2(pin, salt, iterations);
    return _constantTimeEquals(candidate, stored);
  }

  /// Runs off the UI isolate: tens of thousands of HMAC rounds would drop
  /// frames on the keypad animation.
  static Future<String> _hashPbkdf2(String pin, String salt, int iterations) {
    return Isolate.run(() => hashPbkdf2Sync(pin, salt, iterations));
  }

  /// PBKDF2-HMAC-SHA256 with one 32-byte block, encoded with its parameters.
  static String hashPbkdf2Sync(String pin, String salt, int iterations) {
    final hmac = Hmac(sha256, utf8.encode(pin));
    final saltBytes = utf8.encode(salt);
    final block = Uint8List(saltBytes.length + 4)
      ..setAll(0, saltBytes)
      ..setAll(saltBytes.length, const [0, 0, 0, 1]);
    var u = hmac.convert(block).bytes;
    final out = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < out.length; j++) {
        out[j] ^= u[j];
      }
    }
    return 'pbkdf2\$sha256\$$iterations\$${base64.encode(out)}';
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
