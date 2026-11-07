import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/features/profile/domain/entities/contributor.dart';

/// The About page's contributor list: the last one seen, from Hive, at once,
/// then whatever `/contributors` says. A failed refresh keeps the old list.
class ContributorsService {
  ContributorsService({required Dio dio}) : _dio = dio {
    list.value = _readCache();
  }

  final Dio _dio;

  /// Null until something is known, from the cache or the network.
  final ValueNotifier<List<Contributor>?> list = ValueNotifier(null);

  /// True once a refresh has failed with nothing cached to show.
  final ValueNotifier<bool> failed = ValueNotifier(false);

  DateTime? _fetchedAt;
  bool _inFlight = false;

  static const Duration _minRefresh = Duration(minutes: 30);

  Box? get _box {
    try {
      return Hive.box(AppConstants.settingsBox);
    } catch (_) {
      return null;
    }
  }

  List<Contributor>? _readCache() {
    try {
      final raw = _box?.get(AppConstants.contributorsCacheKey);
      if (raw is String && raw.isNotEmpty) {
        final rows = Contributor.listFrom(jsonDecode(raw));
        if (rows.isNotEmpty) return rows;
      }
    } catch (_) {}
    return null;
  }

  Future<void> refresh() async {
    if (_inFlight) return;
    final at = _fetchedAt;
    if (at != null && DateTime.now().difference(at) < _minRefresh) return;
    _inFlight = true;
    failed.value = false;
    try {
      final res = await _dio.get(
        '/contributors',
        options: Options(extra: const {'skipAuthInterceptor': true}),
      );
      final rows = Contributor.listFrom(res.data);
      if (rows.isEmpty) throw StateError('empty contributors');
      _fetchedAt = DateTime.now();
      list.value = rows;
      try {
        await _box?.put(
          AppConstants.contributorsCacheKey,
          jsonEncode([for (final c in rows) c.toJson()]),
        );
      } catch (_) {}
    } catch (e) {
      debugPrint('[contributors] refresh failed: $e');
      if (list.value == null) failed.value = true;
    } finally {
      _inFlight = false;
    }
  }
}
