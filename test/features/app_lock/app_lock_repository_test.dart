import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:local_auth/local_auth.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/app_lock/data/datasources/app_lock_local_data_source.dart';
import 'package:soplay/features/app_lock/data/repositories/app_lock_repository_impl.dart';

class _InMemorySecureStorage implements FlutterSecureStorage {
  final Map<String, String> _storage = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value != null) {
      _storage[key] = value;
    } else {
      _storage.remove(key);
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _storage[key];

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _storage.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLocalAuthentication implements LocalAuthentication {
  bool supported = true;
  bool canCheck = true;
  List<BiometricType> biometrics = [BiometricType.fingerprint];
  bool authSuccess = true;

  @override
  Future<bool> isDeviceSupported() async => supported;

  @override
  Future<bool> get canCheckBiometrics async => canCheck;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => biometrics;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<AuthMessages>? authMessages,
    AuthenticationOptions? options,
  }) async => authSuccess;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory tempDir;
  late HiveService hiveService;
  late _InMemorySecureStorage secureStorage;
  late _FakeLocalAuthentication localAuth;
  late AppLockRepositoryImpl repository;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('kaizoku_app_lock_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(AppConstants.settingsBox);
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    final box = Hive.box(AppConstants.settingsBox);
    await box.clear();

    hiveService = HiveService();
    secureStorage = _InMemorySecureStorage();
    localAuth = _FakeLocalAuthentication();

    final dataSource = AppLockLocalDataSource(
      hiveService: hiveService,
      secureStorage: secureStorage,
      localAuth: localAuth,
    );
    repository = AppLockRepositoryImpl(dataSource);
  });

  test('default state is disabled', () {
    expect(repository.isEnabled, isFalse);
    expect(repository.pinLength, 4);
    expect(repository.isBiometricPreferred, isFalse);
  });

  test('setPin hashes PIN and enables app lock', () async {
    await repository.setPin('1234');

    expect(repository.isEnabled, isTrue);
    expect(repository.pinLength, 4);

    final salt = await secureStorage.read(key: AppConstants.appLockPinSaltSecureKey);
    final hash = await secureStorage.read(key: AppConstants.appLockPinHashSecureKey);

    expect(salt, isNotNull);
    expect(hash, isNotNull);
    expect(salt!.length, greaterThan(10));
    expect(hash!.length, equals(64)); // SHA-256 hex string is 64 chars
  });

  test('verifyPin returns true on correct PIN and false on wrong PIN', () async {
    await repository.setPin('9876');

    final correct = await repository.verifyPin('9876');
    final wrong = await repository.verifyPin('1234');

    expect(correct, isTrue);
    expect(wrong, isFalse);
  });

  test('disable clears secure storage and sets isEnabled to false', () async {
    await repository.setPin('5555');
    expect(repository.isEnabled, isTrue);

    await repository.disable();

    expect(repository.isEnabled, isFalse);
    final salt = await secureStorage.read(key: AppConstants.appLockPinSaltSecureKey);
    final hash = await secureStorage.read(key: AppConstants.appLockPinHashSecureKey);

    expect(salt, isNull);
    expect(hash, isNull);
  });

  test('ensureConsistent auto-disables lock when secureStorage lost keys', () async {
    await repository.setPin('4321');
    expect(repository.isEnabled, isTrue);

    // Simulate secure storage wiped externally while Hive flag remains true
    await secureStorage.delete(key: AppConstants.appLockPinHashSecureKey);

    await repository.ensureConsistent();

    expect(repository.isEnabled, isFalse,
        reason: 'Lock should auto-disable rather than locking user out forever');
  });

  test('biometric detection and authentication', () async {
    final available = await repository.isBiometricAvailable();
    expect(available, isTrue);

    await repository.setBiometricPreferred(true);
    expect(repository.isBiometricPreferred, isTrue);

    final authenticated = await repository.authenticateWithBiometrics('Test Reason');
    expect(authenticated, isTrue);
  });
}
