import 'dart:async';
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

/// Thrown by [UserListsRepositoryImpl.getList] when the server cannot be
/// reached and there is no cached copy to fall back on.
class UserListUnavailable implements Exception {
  const UserListUnavailable();
}

/// One local edit the server has not confirmed yet.
class PendingListOp {
  const PendingListOp({
    required this.kind,
    required this.isAdd,
    required this.entity,
    required this.at,
  });

  final UserListKind kind;
  final bool isAdd;
  final FavoriteEntity entity;
  final int at;

  String get key => '${kind.slug}|${entity.contentUrl}';

  Map<String, dynamic> toJson() => {
    'kind': kind.slug,
    'op': isAdd ? 'add' : 'remove',
    'provider': entity.provider,
    'contentUrl': entity.contentUrl,
    'title': entity.title,
    'thumbnail': entity.thumbnail,
    'at': at,
  };

  static PendingListOp? fromJson(Map m) {
    final kind = UserListKind.values
        .where((k) => k.slug == m['kind'])
        .firstOrNull;
    final url = (m['contentUrl'] ?? '').toString();
    if (kind == null || url.isEmpty) return null;
    return PendingListOp(
      kind: kind,
      isAdd: m['op'] == 'add',
      entity: FavoriteEntity(
        provider: (m['provider'] ?? '').toString(),
        contentUrl: url,
        title: (m['title'] ?? '').toString(),
        thumbnail: (m['thumbnail'] ?? '').toString(),
      ),
      at: (m['at'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Cache-first, server-authoritative, with an outbox for offline edits.
///
/// Writes land in the cache and in a persisted outbox, then are pushed. The
/// outbox holds at most one op per (list, item) — the newest — and is replayed
/// oldest first before every fetch and when connectivity returns. Whatever is
/// still unsent after a fetch is laid back over the server's copy, so a fetch
/// can never silently undo an edit the server has not seen.
class UserListsRepositoryImpl implements UserListsRepository {
  UserListsRepositoryImpl(
    this.remote,
    this.hive, {
    Stream<void>? reconnects,
    int Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch) {
    _reconnectSub = reconnects?.listen((_) => unawaited(flushOutbox()));
  }

  final UserListsRemoteDataSource remote;
  final HiveService hive;
  final int Function() _clock;
  StreamSubscription<void>? _reconnectSub;
  Future<void>? _flushing;

  static const outboxKey = '__pending_ops__';

  Box get _box => Hive.box(ProfileScope.box(AppConstants.userListsBox));

  void dispose() => _reconnectSub?.cancel();

  bool _hasCache(UserListKind kind) => _box.get(kind.slug) is String;

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

  /// Pending ops, oldest first.
  List<PendingListOp> pendingOps() {
    final raw = _box.get(outboxKey);
    if (raw is! String || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final ops = decoded
          .whereType<Map>()
          .map(PendingListOp.fromJson)
          .whereType<PendingListOp>()
          .toList();
      ops.sort((a, b) => a.at.compareTo(b.at));
      return ops;
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveOps(List<PendingListOp> ops) async {
    if (ops.isEmpty) {
      await _box.delete(outboxKey);
      return;
    }
    await _box.put(outboxKey, jsonEncode([for (final o in ops) o.toJson()]));
  }

  Future<void> _enqueue(PendingListOp op) async {
    final ops = pendingOps()..removeWhere((o) => o.key == op.key);
    ops.add(op);
    await _saveOps(ops);
  }

  /// Sends pending ops oldest first. Stops at the first failure so the order
  /// the user made the edits in is the order the server sees them.
  Future<void> flushOutbox() {
    if (!hive.isLoggedIn) return Future.value();
    return _flushing ??= _flush().whenComplete(() => _flushing = null);
  }

  Future<void> _flush() async {
    while (true) {
      final ops = pendingOps();
      if (ops.isEmpty) return;
      final op = ops.first;
      try {
        if (op.isAdd) {
          await remote.add(
            op.kind,
            provider: op.entity.provider,
            contentUrl: op.entity.contentUrl,
            title: op.entity.title,
            thumbnail: op.entity.thumbnail,
          );
        } else {
          await remote.remove(op.kind, op.entity.contentUrl);
        }
      } catch (_) {
        return;
      }
      // Re-read: an edit made while the request was in flight replaces the op
      // under the same key with a newer one, which must stay queued.
      final now = pendingOps()
        ..removeWhere((o) => o.key == op.key && o.at == op.at);
      await _saveOps(now);
    }
  }

  List<FavoriteEntity> _overlay(
    UserListKind kind,
    List<FavoriteEntity> items,
  ) {
    var out = items;
    for (final op in pendingOps()) {
      final touches =
          op.kind == kind ||
          (op.isAdd &&
              op.kind == UserListKind.watched &&
              kind == UserListKind.watchLater);
      if (!touches) continue;
      out = [
        if (op.isAdd && op.kind == kind) op.entity,
        ...out.where((e) => e.contentUrl != op.entity.contentUrl),
      ];
    }
    return out;
  }

  @override
  Future<Result<List<FavoriteEntity>>> getList(UserListKind kind) async {
    // These lists live on the account, so a signed-out user has none. Return
    // the (empty) cache rather than an error — the UI shows a sign-in prompt.
    if (!hive.isLoggedIn) return Success(_cached(kind));
    await flushOutbox();
    try {
      final server = await remote.getList(kind);
      final items = _overlay(kind, [
        for (final m in server)
          FavoriteEntity(
            provider: m.provider,
            contentUrl: m.contentUrl,
            title: m.title,
            thumbnail: m.thumbnail,
          ),
      ]);
      await _store(kind, items);
      return Success(items);
    } catch (_) {
      if (_hasCache(kind) || pendingOps().any((o) => o.kind == kind)) {
        return Success(_cached(kind));
      }
      return const Failure(UserListUnavailable());
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
      await _enqueue(
        PendingListOp(kind: kind, isAdd: true, entity: entity, at: _clock()),
      );
      await flushOutbox();
    }
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> remove(UserListKind kind, String contentUrl) async {
    final existing = _cached(
      kind,
    ).where((e) => e.contentUrl == contentUrl).firstOrNull;
    await _store(
      kind,
      _cached(kind).where((e) => e.contentUrl != contentUrl).toList(growable: false),
    );
    if (hive.isLoggedIn) {
      await _enqueue(
        PendingListOp(
          kind: kind,
          isAdd: false,
          entity:
              existing ??
              FavoriteEntity(
                provider: '',
                contentUrl: contentUrl,
                title: '',
                thumbnail: '',
              ),
          at: _clock(),
        ),
      );
      await flushOutbox();
    }
    return const Success<void>(null);
  }

  @override
  bool contains(UserListKind kind, String contentUrl) =>
      _cached(kind).any((e) => e.contentUrl == contentUrl);
}
