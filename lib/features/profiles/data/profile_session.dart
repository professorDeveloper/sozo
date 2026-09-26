import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/profile_scope.dart';
import 'package:soplay/core/storage/profile_storage.dart';
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
  }) : _remote = remote,
       _isLoggedIn = isLoggedIn,
       _beforeSwitch = beforeSwitch,
       _onScopeChanged = onScopeChanged,
       _settingsOverride = settings {
    _readCache();
  }

  static const String cacheKey = 'household_profiles';
  static const String activeKey = 'household_active';

  final ProfilesRemoteDataSource _remote;
  final bool Function() _isLoggedIn;
  final Future<void> Function()? _beforeSwitch;
  final Future<void> Function({required bool resync})? _onScopeChanged;
  final Box? _settingsOverride;

  Box get _settings => _settingsOverride ?? Hive.box(AppConstants.settingsBox);

  List<HouseholdProfile> _profiles = const [];
  HouseholdProfile? _active;
  int _max = 4;
  bool _chosenThisRun = false;
  bool _loaded = false;

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
      _isLoggedIn() && _profiles.length > 1 && !_chosenThisRun;

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
      if (shouldPick) pickRequests.value++;
    } else if (fresh != current) {
      await _adopt(fresh);
    }
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

  Future<HouseholdProfile> verifyPin(String id, String pin) =>
      _remote.verifyPin(id, pin);

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
    if (_active?.id == id) {
      await _switchTo(defaultProfile, resync: true);
      _chosenThisRun = false;
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
    await ProfileStorage.deleteAll(_settings, known: known);
    await _settings.delete(cacheKey);
    await _settings.delete(activeKey);
    await _onScopeChanged?.call(resync: false);
    notifyListeners();
  }
}
