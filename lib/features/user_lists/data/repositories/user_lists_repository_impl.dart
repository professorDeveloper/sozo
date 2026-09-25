import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/profile_scope.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/my_list/domain/entities/favorite_entity.dart';
import 'package:soplay/features/user_lists/data/datasources/user_lists_remote_data_source.dart';
import 'package:soplay/features/user_lists/domain/entities/user_list_kind.dart';
import 'package:soplay/features/user_lists/domain/repositories/user_lists_repository.dart';

/// Cache-first, server-authoritative.
///
/// The same shape [MyListRepositoryImpl] uses, and for the same reason: these
/// lists are read on screens that must render instantly and must not go blank
/// on a flaky connection. So every read serves the cache, a successful fetch
/// replaces it, and a failed fetch leaves the last good copy in place.
///
/// Writes are applied to the cache FIRST so the button flips immediately, then
/// pushed. A failed push leaves the local edit standing — the next successful
/// [getList] reconciles it against the server, which is the authority.
class UserListsRepositoryImpl implements UserListsRepository {
  UserListsRepositoryImpl(this.remote, this.hive);

  final UserListsRemoteDataSource remote;
  final HiveService hive;

  Box get _box => Hive.box(ProfileScope.box(AppConstants.userListsBox));

  List<FavoriteEntity> _cached(UserListKind kind) {
    final raw = _box.get(kind.slug);
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (e) => FavoriteEntity(
              provider: (e['provider'] ?? '').toString(),
              contentUrl: (e['contentUrl'] ?? '').toString(),
              title: (e['title'] ?? '').toString(),
              thumbnail: (e['thumbnail'] ?? '').toString(),
            ),
          )
          .where((e) => e.contentUrl.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _store(UserListKind kind, List<FavoriteEntity> items) async {
    await _box.put(
      kind.slug,
      jsonEncode([
        for (final e in items)
          {
            'provider': e.provider,
            'contentUrl': e.contentUrl,
            'title': e.title,
            'thumbnail': e.thumbnail,
          },
      ]),
    );
  }

  @override
  Future<Result<List<FavoriteEntity>>> getList(UserListKind kind) async {
    // These lists live on the account, so a signed-out user has none. Return
    // the (empty) cache rather than an error — the UI shows a sign-in prompt.
    if (!hive.isLoggedIn) return Success(_cached(kind));
    try {
      final server = await remote.getList(kind);
      final items = server
          .map(
            (m) => FavoriteEntity(
              provider: m.provider,
              contentUrl: m.contentUrl,
              title: m.title,
              thumbnail: m.thumbnail,
            ),
          )
          .toList(growable: false);
      await _store(kind, items);
      return Success(items);
    } catch (_) {
      return Success(_cached(kind));
    }
  }

  @override
  Future<Result<void>> add(UserListKind kind, FavoriteEntity entity) async {
    final next = [
      entity,
      ..._cached(kind).where((e) => e.contentUrl != entity.contentUrl),
    ];
    await _store(kind, next);

    // Mirror the server's rule: something marked Watched is no longer pending.
    // Done locally too, or the Watch Later tab would keep showing it until the
    // next fetch. See addToList in the backend's authService.
    if (kind == UserListKind.watched) {
      await _store(
        UserListKind.watchLater,
        _cached(
          UserListKind.watchLater,
        ).where((e) => e.contentUrl != entity.contentUrl).toList(growable: false),
      );
    }

    if (hive.isLoggedIn) {
      try {
        await remote.add(
          kind,
          provider: entity.provider,
          contentUrl: entity.contentUrl,
          title: entity.title,
          thumbnail: entity.thumbnail,
        );
      } catch (_) {
        // Kept locally; reconciled on the next successful getList.
      }
    }
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> remove(UserListKind kind, String contentUrl) async {
    await _store(
      kind,
      _cached(kind).where((e) => e.contentUrl != contentUrl).toList(growable: false),
    );
    if (hive.isLoggedIn) {
      try {
        await remote.remove(kind, contentUrl);
      } catch (_) {}
    }
    return const Success<void>(null);
  }

  @override
  bool contains(UserListKind kind, String contentUrl) =>
      _cached(kind).any((e) => e.contentUrl == contentUrl);
}
