import 'package:flutter/foundation.dart';

import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/social/data/social_remote_data_source.dart';
import 'package:soplay/features/social/domain/social_models.dart';

/// App-wide social state: the counts behind the Profile badge, and a revision
/// every open screen listens to, so accepting a request on someone's profile
/// also moves them into the Friends tab without a manual refresh.
class SocialService {
  SocialService({required this.remote, required HiveService hive})
    : _hive = hive;

  final SocialRemoteDataSource remote;
  final HiveService _hive;

  final ValueNotifier<SocialOverview> overview = ValueNotifier(
    SocialOverview.empty,
  );
  final ValueNotifier<int> revision = ValueNotifier(0);

  bool get available => _hive.isLoggedIn;

  String? get myUsername => _hive.getUser()?.username;

  Future<void> refreshOverview() async {
    if (!available) {
      overview.value = SocialOverview.empty;
      return;
    }
    try {
      overview.value = await remote.overview();
    } catch (_) {}
  }

  void _changed() {
    revision.value++;
    refreshOverview();
  }

  Future<RequestOutcome> sendRequest({String? userId, String? username}) async {
    final out = await remote.sendRequest(userId: userId, username: username);
    _changed();
    return out;
  }

  Future<RequestOutcome> accept(String requestId) async {
    final out = await remote.acceptRequest(requestId);
    _changed();
    return out;
  }

  Future<void> deleteRequest(String requestId) async {
    await remote.deleteRequest(requestId);
    _changed();
  }

  Future<void> removeFriend(String userId) async {
    await remote.removeFriend(userId);
    _changed();
  }

  Future<void> block(String userId) async {
    await remote.block(userId);
    _changed();
  }

  Future<void> unblock(String userId) async {
    await remote.unblock(userId);
    _changed();
  }

  void clear() => overview.value = SocialOverview.empty;
}
