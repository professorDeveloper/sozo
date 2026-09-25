import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/jellyfin/data/jellyfin_server_store.dart';
import 'package:soplay/features/jellyfin/domain/jellyfin_server.dart';

import 'jellyfin_fakes.dart';

void main() {
  test('saves, replaces by server id and removes', () async {
    final store = JellyfinServerStore(box: () => null);
    var changes = 0;
    store.revision.addListener(() => changes++);

    await store.save(testServer);
    await store.save(
      testServer.copyWith(accessToken: 'new', hiddenLibraries: ['lib2']),
    );
    expect(store.servers(), hasLength(1));
    expect(store.byId('srv1')!.accessToken, 'new');
    expect(store.byId('srv1')!.shows('lib2'), isFalse);
    expect(store.byId('srv1')!.providerId, 'jf:srv1');

    await store.remove('srv1');
    expect(store.servers(), isEmpty);
    expect(changes, 3);
  });

  test('keeps one device id per install', () {
    final store = JellyfinServerStore(box: () => null);
    final id = store.deviceId;
    expect(id, hasLength(32));
    expect(store.deviceId, id);
  });

  test('a record without a session is dropped, not half-loaded', () {
    expect(JellyfinServer.fromJson({'id': 'x', 'baseUrl': 'http://h'}), isNull);
    final s = JellyfinServer.fromJson(testServer.toJson())!;
    expect(s.baseUrl, testServer.baseUrl);
    expect(s.host, 'nas:8096');
  });
}
