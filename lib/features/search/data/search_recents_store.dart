import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/profile_scope.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';

/// The last queries the user actually ran, so the idle search screen has
/// something on it. Every operation is best-effort: search must keep working
/// even if the settings box is unavailable (tests, first run).
class SearchRecentsStore {
  static const String _key = 'search_recent_queries';
  static const int maxEntries = 8;

  Box? get _box {
    try {
      return Hive.box(AppConstants.settingsBox);
    } catch (_) {
      return null;
    }
  }

  /// Always growable, and always a fresh list.
  ///
  /// This returned `const []` when there was nothing stored, and every caller
  /// below then mutated what it got back. On a device that had never searched
  /// — which is every device, since the write below was never reached to
  /// create the key — `add` threw "Cannot remove from an unmodifiable list"
  /// out of [SearchBloc], between the fetch that had already succeeded and the
  /// emit that would have shown its results. Search fetched, and then showed
  /// nothing, on every query.
  List<String> load() {
    final raw = _box?.get(ProfileScope.key(_key));
    if (raw is! List) return <String>[];
    return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }

  /// Whether the app is currently promising to remember nothing.
  ///
  /// Guarded by `isRegistered` the same way history's check is: this store is
  /// constructed in tests and on first run with no DI behind it, and a private
  /// mode that throws is worse than one that is off.
  bool get _incognito =>
      getIt.isRegistered<HiveService>() && getIt<HiveService>().isIncognito;

  Future<List<String>> add(String query) async {
    final q = query.trim();
    if (q.isEmpty) return load();
    // The most visible leak there was: every query typed in incognito was
    // written here, and the idle Search screen draws this list. Close the
    // player, go back to Search, and the private session was listed on screen.
    //
    // Enforced at the write rather than in the bloc, so the next caller cannot
    // forget — the same reasoning as HistoryService.save.
    if (_incognito) return load();
    final list = load()
      ..removeWhere((e) => e.toLowerCase() == q.toLowerCase())
      ..insert(0, q);
    final trimmed = list.take(maxEntries).toList();
    await _write(trimmed);
    return trimmed;
  }

  Future<List<String>> remove(String query) async {
    final list = load()
      ..removeWhere((e) => e.toLowerCase() == query.trim().toLowerCase());
    await _write(list);
    return list;
  }

  Future<List<String>> clear() async {
    await _write(const []);
    return <String>[];
  }

  Future<void> _write(List<String> list) async {
    try {
      await _box?.put(ProfileScope.key(_key), list);
    } catch (_) {}
  }
}
