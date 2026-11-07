import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/profile_scope.dart';
import 'package:soplay/core/storage/profile_storage.dart';
import 'package:soplay/features/app_lock/domain/entities/pin_check.dart';
import 'package:soplay/features/profiles/data/profile_pin_store.dart';
import 'package:soplay/features/profiles/data/profiles_remote_data_source.dart';
import 'package:soplay/features/profiles/domain/household_profile.dart';

/// The account's household profiles and which one this device is acting as.
///
/// The list and the active choice are cached in the settings box (device-level
/// keys), so launch can decide on the picker and open the right boxes before
/// any request has been made.
class ProfileSession extends ChangeNotifier {
  ProfileSession({
    required ProfilesRemoteDataSource remote,
    required bool Function() isLoggedIn,
    Future<void> Function()? beforeSwitch,
    Future<void> Function({required bool resync})? onScopeChanged,
    Box? settings,
    ProfilePinStore? pins,
    String? Function()? accountId,
  }) : _remote = remote,
       _isLoggedIn = isLoggedIn,
       _pins = pins,
       _accountId = accountId,
       _beforeSwitch = beforeSwitch,
       _onScopeChanged = onScopeChanged,
       _settingsOverride = settings {
    _readCache();
  }

  static const String cacheKey = 'household_profiles';
  static const String activeKey = 'household_active';
  static const String askOnLaunchKey = 'household_ask_on_launch';

  final ProfilesRemoteDataSource _remote;
  final bool Function() _isLoggedIn;
  final Future<void> Function()? _beforeSwitch;
  final Future<void> Function({required bool resync})? _onScopeChanged;
  final Box? _settingsOverride;
  final ProfilePinStore? _pins;
  final String? Function()? _accountId;

  String get _account => _accountId?.call() ?? '';

  Box get _settings => _settingsOverride ?? Hive.box(AppConstants.settingsBox);

  List<HouseholdProfile> _profiles = const [];
  HouseholdProfile? _active;
  int _max = 4;
  bool _chosenThisRun = false;
  bool _loaded = false;

  /// The active profile came from the previous run rather than from a choice
  /// or a sign-in in this one.
  bool _restored = false;

  /// Profiles whose PIN was entered (or biometrics passed) in this run.
  final Set<String> _unlocked = {};

  /// Bumped when the app should show the picker without being asked: the
  /// active profile was deleted elsewhere, or a sign-in found several.
  final ValueNotifier<int> pickRequests = ValueNotifier<int>(0);

  List<HouseholdProfile> get profiles => _profiles;
  HouseholdProfile? get active => _active;
  int get max => _max;

  /// A household's cap, whatever an older server still reports.
  static const int maxProfiles = 4;

  /// True once the list has come from the server in this run.
  bool get loaded => _loaded;
  bool get canAdd => _profiles.length < _max;

  /// The server refuses profile management from a kids profile.
  bool get canManage => !(_active?.isKids ?? false);
  /// Whether an account is signed in on this device at all. Profiles belong
  /// to an account, so without one there is nothing to pick.
  bool get signedIn => _isLoggedIn();

  bool get shouldPick =>
      _isLoggedIn() &&
      _profiles.length > 1 &&
      !_chosenThisRun &&
      !opensLastProfile(
        askOnLaunch: askOnLaunch,
        restored: _restored ? _active : null,
      );

  /// "Ask who's watching on launch". Off, a launch goes straight into the
  /// profile the previous run ended in.
  bool get askOnLaunch => _settings.get(askOnLaunchKey) != false;

  Future<void> setAskOnLaunch(bool value) async {
    await _settings.put(askOnLaunchKey, value);
    notifyListeners();
  }

  /// Whether a launch skips the picker for the profile the last run ended in.
  /// Never for one with a PIN: the picker is where that PIN is asked.
  static bool opensLastProfile({
    required bool askOnLaunch,
    required HouseholdProfile? restored,
  }) => !askOnLaunch && restored != null && !restored.hasPin;

  /// Whether opening [profile] has to ask for its PIN. Not for the active
  /// profile once it has been unlocked in this run.
  bool needsPin(HouseholdProfile profile) =>
      profile.hasPin &&
      !(profile.id == _active?.id && _unlocked.contains(profile.id));

  HouseholdProfile? get defaultProfile {
    for (final p in _profiles) {
      if (p.isDefault) return p;
    }
    return null;
  }

  HouseholdProfile? byId(String id) {
    for (final p in _profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Called from `_initHive`, before anything reads a profile box.
  static Future<void> restore(Box settings, {required bool loggedIn}) async {
    final active = _decodeProfile(settings.get(activeKey));
    if (active == null || !loggedIn) {
      ProfileScope.reset();
      return;
    }
    try {
      await ProfileStorage.open(active.namespace);
      ProfileScope.set(
        namespace: active.namespace,
        remoteId: active.id,
        kids: active.isKids,
      );
    } catch (e) {
      // The default profile's boxes are always there; better its data than
      // no app.
      debugPrint('[ProfileSession] restore failed, using default: $e');
      ProfileScope.reset();
    }
  }

  void _readCache() {
    try {
      final raw = _settings.get(cacheKey);
      if (raw is String && raw.isNotEmpty) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        _max = math.min((data['max'] as num?)?.toInt() ?? 4, maxProfiles);
        _profiles = [
          for (final p in (data['profiles'] as List? ?? const []))
            if (p is Map) HouseholdProfile.fromJson(p.cast<String, dynamic>()),
        ];
      }
      final active = _decodeProfile(_settings.get(activeKey));
      // Only trusted if [restore] actually opened its boxes.
      _active = active != null && active.id == ProfileScope.remoteId
          ? active
          : null;
      _restored = _active != null;
    } catch (_) {
      _profiles = const [];
      _active = null;
    }
  }

  static HouseholdProfile? _decodeProfile(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      final p = HouseholdProfile.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      return p.id.isEmpty ? null : p;
    } catch (_) {
      return null;
    }
  }

  Future<void> _persist() async {
    await _settings.put(
      cacheKey,
      jsonEncode({
        'max': _max,
        'profiles': [for (final p in _profiles) p.toJson()],
      }),
    );
    final active = _active;
    if (active == null) {
      await _settings.delete(activeKey);
    } else {
      await _settings.put(activeKey, jsonEncode(active.toJson()));
    }
  }

  Future<bool>? _refreshing;

  /// Fetches the list. Returns false when the server could not be asked.
  Future<bool> refresh() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<bool> _refresh() async {
    if (!_isLoggedIn()) return false;
    final ProfilesListing listing;
    try {
      listing = await _remote.list();
    } on ProfileException {
      return false;
    }
    if (!_isLoggedIn()) return false;
    _profiles = List.unmodifiable(listing.profiles);
    _max = math.min(listing.max, maxProfiles);
    _loaded = true;

    final current = _active;
    final fresh = current == null ? null : byId(current.id);
    if (current == null) {
      // First listing on this device: the data here is the default
      // profile's, which is where an app without profiles was writing.
      final def = defaultProfile;
      _active = def;
      ProfileScope.set(remoteId: def?.id);
    } else if (fresh == null || listing.activeProfileId == null) {
      await _switchTo(defaultProfile, resync: true);
      _chosenThisRun = false;
      _restored = false;
      if (shouldPick) pickRequests.value++;
    } else if (fresh != current) {
      await _adopt(fresh);
    }
    _unlocked.removeWhere((id) => !(byId(id)?.hasPin ?? false));
    await _pins?.retain(_account, {
      for (final p in _profiles)
        if (p.hasPin) p.id,
    });
    await _persist();
    notifyListeners();
    return true;
  }

  /// Makes [profile] the one this device acts as. A PIN, if it has one, must
  /// already have been checked with [verifyPin].
  Future<void> activate(HouseholdProfile profile) async {
    if (_active?.id != profile.id) {
      await _switchTo(profile, resync: true);
    }
    _chosenThisRun = true;
    await _persist();
    notifyListeners();
  }

  /// For accounts with one profile, and for "keep watching as" flows that
  /// never showed the picker.
  void markChosen() => _chosenThisRun = true;

  Future<void> _switchTo(
    HouseholdProfile? profile, {
    required bool resync,
  }) async {
    await _beforeSwitch?.call();
    final ns = profile?.namespace;
    await ProfileStorage.open(ns);
    ProfileScope.set(
      namespace: ns,
      remoteId: profile?.id,
      kids: profile?.isKids ?? false,
    );
    _active = profile;
    await _onScopeChanged?.call(resync: resync);
  }

  /// The active profile changed on the server (renamed, kids flag flipped),
  /// but it is still the same profile, so its data stays where it is.
  Future<void> _adopt(HouseholdProfile fresh) async {
    final kidsChanged = fresh.isKids != _active?.isKids;
    _active = fresh;
    ProfileScope.set(
      namespace: fresh.namespace,
      remoteId: fresh.id,
      kids: fresh.isKids,
    );
    if (kidsChanged) await _onScopeChanged?.call(resync: false);
  }

  /// Checks [pin] with the server, or, only when the server can't be
  /// reached, with what this device kept from the last time it was accepted.
  Future<HouseholdProfile> verifyPin(String id, String pin) async {
    try {
      final profile = await _remote.verifyPin(id, pin);
      _unlocked.add(id);
      await _remember(id, pin);
      return profile;
    } on ProfileException catch (e) {
      final pins = _pins;
      final known = byId(id);
      if (!e.isUnreachable || pins == null || known == null) rethrow;
      final result = await pins.check(_account, id, pin);
      switch (result.outcome) {
        case PinCheck.ok:
          _unlocked.add(id);
          return known;
        case PinCheck.wrong:
          throw const ProfileException('Wrong PIN', code: 'PIN_INVALID');
        case PinCheck.lockedOut:
          throw ProfileException(
            'Too many attempts',
            code: 'PIN_LOCKED',
            retryAt: result.retryAt,
          );
        case PinCheck.unavailable:
          throw const ProfileException(
            'PIN not known offline',
            code: 'PIN_NOT_ON_DEVICE',
          );
      }
    }
  }

  Future<void> _remember(String id, String pin) async {
    try {
      await _pins?.remember(_account, id, pin);
    } catch (_) {}
  }

  /// Whether [id] can be opened with a fingerprint or face on this device.
  Future<bool> canUnlockWithBiometric(String id) async =>
      await _pins?.canUnlockWithBiometric(_account, id) ?? false;

  Future<bool> unlockWithBiometric(String id, String reason) async {
    final ok =
        await _pins?.unlockWithBiometric(_account, id, reason) ?? false;
    if (ok) _unlocked.add(id);
    return ok;
  }

  Future<bool> shouldOfferBiometric(String id) async =>
      await _pins?.shouldOfferBiometric(_account, id) ?? false;

  Future<void> markBiometricOffered(String id) async {
    await _pins?.markBiometricOffered(_account, id);
  }

  /// Whether [id]'s PIN has been accepted here, so biometrics can stand in.
  Future<bool> hasLocalPin(String id) async =>
      await _pins?.has(_account, id) ?? false;

  Future<bool> biometricEnabled(String id) async =>
      await _pins?.biometricEnabled(_account, id) ?? false;

  Future<bool> biometricsAvailable() async =>
      await _pins?.biometricsAvailable() ?? false;

  /// Turning it on asks for a fingerprint or face first, so it is the person
  /// holding the device who is enrolled. Returns whether it is now on.
  Future<bool> setBiometric(String id, bool on, {String? reason}) async {
    final pins = _pins;
    if (pins == null) return false;
    if (on && !await pins.authenticate(reason ?? '')) return false;
    await pins.setBiometric(_account, id, on);
    notifyListeners();
    return on;
  }

  Future<HouseholdProfile> create({
    required String name,
    String? avatar,
    String? color,
    bool isKids = false,
    String? pin,
  }) async {
    final created = await _remote.create(
      name: name,
      avatar: avatar,
      color: color,
      isKids: isKids,
      pin: pin,
    );
    if (pin != null) await _remember(created.id, pin);
    _profiles = List.unmodifiable([..._profiles, created]);
    await _persist();
    notifyListeners();
    return created;
  }

  Future<HouseholdProfile> update(
    String id,
    Map<String, dynamic> changes, {
    String? currentPin,
  }) async {
    final updated = await _remote.update(id, changes, currentPin: currentPin);
    if (changes.containsKey('pin')) {
      final pin = changes['pin'];
      if (pin is String) {
        await _remember(id, pin);
      } else {
        _unlocked.remove(id);
        await _pins?.forget(_account, id);
      }
    }
    _profiles = List.unmodifiable([
      for (final p in _profiles) p.id == id ? updated : p,
    ]);
    if (_active?.id == id) await _adopt(updated);
    await _persist();
    notifyListeners();
    return updated;
  }

  Future<void> delete(String id, {String? currentPin}) async {
    final target = byId(id);
    await _remote.delete(id, currentPin: currentPin);
    _unlocked.remove(id);
    await _pins?.forget(_account, id);
    if (_active?.id == id) {
      await _switchTo(defaultProfile, resync: true);
      _chosenThisRun = false;
      _restored = false;
    }
    _profiles = List.unmodifiable(_profiles.where((p) => p.id != id));
    final ns = target?.namespace ?? id;
    await ProfileStorage.delete(ns, _settings);
    await _persist();
    notifyListeners();
  }

  /// Sign-out: every extra profile's data leaves the device, and the default
  /// profile's boxes are what the rest of sign-out then clears.
  Future<void> forgetAll() async {
    final known = [
      for (final p in _profiles)
        if (p.namespace != null) p.namespace!,
      if (_active?.namespace != null) _active!.namespace!,
    ];
    ProfileScope.reset();
    _profiles = const [];
    _active = null;
    _chosenThisRun = false;
    _loaded = false;
    _restored = false;
    _unlocked.clear();
    await _pins?.clear();
    await ProfileStorage.deleteAll(_settings, known: known);
    await _settings.delete(cacheKey);
    await _settings.delete(activeKey);
    await _onScopeChanged?.call(resync: false);
    notifyListeners();
  }
}
