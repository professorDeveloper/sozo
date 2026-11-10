import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:soplay/features/app_lock/data/pin_secrets.dart';
import 'package:soplay/features/app_lock/domain/entities/pin_check.dart';

/// Lets a profile PIN be checked while the server can't be asked.
///
/// After the server accepts a profile's PIN on this device, a salted PBKDF2
/// hash of it is kept in secure storage, per account and profile, with its
/// own wrong-guess backoff and the biometric choice for that profile. The PIN
/// itself is never stored.
class ProfilePinStore {
  ProfilePinStore({
    FlutterSecureStorage? secureStorage,
    DeviceBiometrics? biometrics,
    DateTime Function()? clock,
    this.iterations = PinHash.iterations,
  }) : _secure =
           secureStorage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(encryptedSharedPreferences: true),
             iOptions: IOSOptions(
               accessibility: KeychainAccessibility.first_unlock,
             ),
           ),
       _biometrics = biometrics ?? DeviceBiometrics(),
       _now = clock ?? DateTime.now;

  /// One secure entry for every profile, so sign-out can clear them all
  /// without knowing which account they belonged to.
  static const String storageKey = 'profile_pin_verifiers';

  final FlutterSecureStorage _secure;
  final DeviceBiometrics _biometrics;
  final DateTime Function() _now;
  final int iterations;

  Future<void> _queue = Future.value();

  /// Runs [run] after every earlier read-modify-write has finished.
  Future<T> _locked<T>(Future<T> Function() run) {
    final next = _queue.then((_) => run());
    _queue = next.then((_) {}, onError: (_) {});
    return next;
  }

  static String _key(String account, String profile) => '$account:$profile';

  Future<Map<String, Map<String, dynamic>>> _readAll() async {
    try {
      final raw = await _secure.read(key: storageKey);
      if (raw == null || raw.isEmpty) return {};
      final data = jsonDecode(raw);
      if (data is! Map) return {};
      return {
        for (final e in data.entries)
          if (e.value is Map)
            e.key.toString(): (e.value as Map).cast<String, dynamic>(),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeAll(Map<String, Map<String, dynamic>> all) async {
    try {
      if (all.isEmpty) {
        await _secure.delete(key: storageKey);
      } else {
        await _secure.write(key: storageKey, value: jsonEncode(all));
      }
    } catch (_) {}
  }

  Future<T> _edit<T>(
    T Function(Map<String, Map<String, dynamic>> all) change,
  ) => _locked(() async {
    final all = await _readAll();
    final out = change(all);
    await _writeAll(all);
    return out;
  });

  Future<Map<String, dynamic>?> _entry(String account, String profile) async =>
      (await _readAll())[_key(account, profile)];

  /// Keeps a verifier for [pin], replacing any older one. The biometric
  /// choice survives a PIN change; the wrong-guess count does not.
  Future<void> remember(String account, String profile, String pin) async {
    final salt = PinHash.newSalt();
    final hash = await PinHash.hash(pin, salt, iterations);
    await _edit((all) {
      final key = _key(account, profile);
      final old = all[key] ?? const {};
      all[key] = {
        's': salt,
        'h': hash,
        if (old['b'] == true) 'b': true,
        if (old['o'] == true) 'o': true,
      };
    });
  }

  Future<bool> has(String account, String profile) async {
    final e = await _entry(account, profile);
    return e != null && e['s'] is String && e['h'] is String;
  }

  /// [PinCheck.unavailable] when no PIN has been accepted here for it.
  Future<PinCheckResult> check(
    String account,
    String profile,
    String pin,
  ) async {
    final key = _key(account, profile);
    final e = await _entry(account, profile);
    final salt = e?['s'];
    final hash = e?['h'];
    if (salt is! String || hash is! String) {
      return const PinCheckResult.unavailable();
    }
    final until = _lockedUntil(e!);
    if (until != null) return PinCheckResult.lockedOut(until);

    final ok = await PinHash.verify(pin, salt, hash);
    return _edit((all) {
      final current = all[key];
      if (current == null) return const PinCheckResult.unavailable();
      if (ok) {
        current
          ..remove('f')
          ..remove('u');
        return const PinCheckResult.ok();
      }
      final failures = ((current['f'] as num?)?.toInt() ?? 0) + 1;
      final result = PinBackoff.afterFailure(failures, _now());
      current['f'] = failures;
      final retryAt = result.retryAt;
      if (retryAt != null) current['u'] = retryAt.millisecondsSinceEpoch;
      return result;
    });
  }

  DateTime? _lockedUntil(Map<String, dynamic> e) {
    final ms = (e['u'] as num?)?.toInt();
    if (ms == null) return null;
    final until = DateTime.fromMillisecondsSinceEpoch(ms);
    return until.isAfter(_now()) ? until : null;
  }

  Future<void> forget(String account, String profile) =>
      _edit((all) => all.remove(_key(account, profile)));

  /// Drops [account]'s verifiers for every profile not in [withPin]: deleted
  /// elsewhere, or no longer protected.
  Future<void> retain(String account, Set<String> withPin) => _edit((all) {
    all.removeWhere((key, _) {
      if (!key.startsWith('$account:')) return false;
      return !withPin.contains(key.substring(account.length + 1));
    });
  });

  /// Sign-out.
  Future<void> clear() => _locked(() => _writeAll({}));

  Future<bool> biometricsAvailable() => _biometrics.isAvailable();

  Future<bool> biometricEnabled(String account, String profile) async {
    final e = await _entry(account, profile);
    return e != null && e['b'] == true && e['h'] is String;
  }

  /// Only for a profile that already has a verifier here.
  Future<void> setBiometric(String account, String profile, bool on) =>
      _edit((all) {
        final e = all[_key(account, profile)];
        if (e == null) return;
        if (on) {
          e['b'] = true;
        } else {
          e.remove('b');
        }
        e['o'] = true;
      });

  /// Whether to suggest biometric unlock for [profile]: a PIN was accepted
  /// here, it isn't on yet, it hasn't been suggested before, and the device
  /// can do it.
  Future<bool> shouldOfferBiometric(String account, String profile) async {
    final e = await _entry(account, profile);
    if (e == null || e['h'] is! String) return false;
    if (e['b'] == true || e['o'] == true) return false;
    return _biometrics.isAvailable();
  }

  Future<void> markBiometricOffered(String account, String profile) =>
      _edit((all) => all[_key(account, profile)]?['o'] = true);

  Future<bool> canUnlockWithBiometric(String account, String profile) async {
    if (!await biometricEnabled(account, profile)) return false;
    return _biometrics.isAvailable();
  }

  Future<bool> authenticate(String reason) => _biometrics.authenticate(reason);

  Future<bool> unlockWithBiometric(
    String account,
    String profile,
    String reason,
  ) async {
    if (!await biometricEnabled(account, profile)) return false;
    final ok = await _biometrics.authenticate(reason);
    if (ok) {
      await _edit((all) {
        all[_key(account, profile)]
          ?..remove('f')
          ..remove('u');
      });
    }
    return ok;
  }
}
