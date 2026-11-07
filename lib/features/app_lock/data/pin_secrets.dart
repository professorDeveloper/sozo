import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:local_auth/local_auth.dart';
import 'package:soplay/features/app_lock/domain/entities/pin_check.dart';

/// Salted PBKDF2 for a PIN kept on the device: the app lock's and the offline
/// check of a profile PIN.
abstract final class PinHash {
  /// PBKDF2 rounds for a new hash. A PIN has at most a million values, so the
  /// hash is only ever a speed bump for someone holding a copy of the stored
  /// secret; the real protection is that the secret sits in the platform
  /// keystore and that guessing on the device is rate-limited. The count is
  /// stored with the hash, so it can be raised later without invalidating
  /// anyone's PIN.
  static const int iterations = 60000;

  static String newSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// Runs off the UI isolate: tens of thousands of HMAC rounds would drop
  /// frames on the keypad animation.
  static Future<String> hash(
    String pin,
    String salt, [
    int rounds = iterations,
  ]) => Isolate.run(() => hashSync(pin, salt, rounds));

  /// PBKDF2-HMAC-SHA256 with one 32-byte block, encoded with its parameters.
  static String hashSync(String pin, String salt, int rounds) {
    final hmac = Hmac(sha256, utf8.encode(pin));
    final saltBytes = utf8.encode(salt);
    final block = Uint8List(saltBytes.length + 4)
      ..setAll(0, saltBytes)
      ..setAll(saltBytes.length, const [0, 0, 0, 1]);
    var u = hmac.convert(block).bytes;
    final out = Uint8List.fromList(u);
    for (var i = 1; i < rounds; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < out.length; j++) {
        out[j] ^= u[j];
      }
    }
    return 'pbkdf2\$sha256\$$rounds\$${base64.encode(out)}';
  }

  static bool isPbkdf2(String stored) => stored.startsWith('pbkdf2\$');

  /// Whether [pin] matches a [stored] value made by [hash].
  static Future<bool> verify(String pin, String salt, String stored) async {
    // pbkdf2$sha256$<iterations>$<base64 key>
    final parts = stored.split('\$');
    if (parts.length != 4 || parts[1] != 'sha256') return false;
    final rounds = int.tryParse(parts[2]);
    if (rounds == null || rounds <= 0) return false;
    final candidate = await hash(pin, salt, rounds);
    return constantTimeEquals(candidate, stored);
  }

  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

/// How many wrong guesses in a row are free, and the growing wait after them.
abstract final class PinBackoff {
  static const int freeAttempts = 5;

  /// The first wait; it doubles with each further wrong guess, up to [maxWait].
  static const Duration firstWait = Duration(seconds: 30);
  static const Duration maxWait = Duration(hours: 1);

  /// The wait imposed after the [failures]-th wrong guess in a row, or null
  /// while guesses are still free.
  static Duration? waitAfter(int failures) {
    if (failures < freeAttempts) return null;
    final doublings = min(failures - freeAttempts, 20);
    final wait = firstWait * pow(2, doublings).toInt();
    return wait > maxWait ? maxWait : wait;
  }

  /// What the [failures]-th wrong guess in a row, made at [now], comes to.
  static PinCheckResult afterFailure(int failures, DateTime now) {
    final wait = waitAfter(failures);
    if (wait == null) return PinCheckResult.wrong(freeAttempts - failures);
    return PinCheckResult.lockedOut(now.add(wait));
  }
}

/// Fingerprint or face, through `local_auth`. Never throws.
class DeviceBiometrics {
  DeviceBiometrics([LocalAuthentication? localAuth])
    : _localAuth = localAuth ?? LocalAuthentication();

  final LocalAuthentication _localAuth;

  Future<bool> isAvailable() async {
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

  Future<bool> authenticate(String reason) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
