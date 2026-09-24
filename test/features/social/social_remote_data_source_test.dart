import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/social/data/social_remote_data_source.dart';
import 'package:soplay/features/social/domain/social_models.dart';

import 'social_fakes.dart';

void main() {
  late FakeSocialAdapter adapter;
  late SocialRemoteDataSource remote;

  void serve(Map<String, SocialRoute> routes) {
    adapter = FakeSocialAdapter(routes);
    remote = SocialRemoteDataSource(dio: fakeDio(adapter));
  }

  test('search sends the query and reads relations', () async {
    serve({
      'GET /api/social/users/search': (_) => {
        'items': [
          {...userJson('aziz'), 'relation': 'outgoing', 'requestId': 'r1'},
        ],
      },
    });
    final results = await remote.search('az');
    expect(adapter.requests.single.uri.queryParameters['q'], 'az');
    expect(results.single.relation, SocialRelation.outgoing);
    expect(results.single.requestId, 'r1');
  });

  test('a username is escaped into the path', () async {
    serve({
      'GET /api/social/users/a%20b': (_) => {
        'user': userJson('a b'),
        'relation': 'none',
      },
    });
    final p = await remote.profile('a b');
    expect(p.user.username, 'a b');
    expect(adapter.requests.single.uri.toString(), contains('a%20b'));
  });

  test('the feed passes the cursor back and reads the next one', () async {
    serve({
      'GET /api/social/feed': (o) => {
        'items': [activityJson('x', actor: userJson('bek'))],
        'nextCursor': o.queryParameters['cursor'] == null ? 'n1' : null,
      },
    });
    final first = await remote.feed();
    expect(first.nextCursor, 'n1');
    expect(first.items.single.actor?.username, 'bek');
    final second = await remote.feed(cursor: 'n1');
    expect(second.nextCursor, isNull);
    expect(adapter.requests.last.queryParameters['cursor'], 'n1');
  });

  test('a request is sent by id, and by username only without one', () async {
    serve({
      'POST /api/social/requests': (_) => {
        'relation': 'outgoing',
        'requestId': 'r9',
        'user': userJson('aziz'),
      },
    });
    final out = await remote.sendRequest(userId: 'u1', username: 'ignored');
    expect(adapter.requests.last.data, {'userId': 'u1'});
    expect(out.requestId, 'r9');

    await remote.sendRequest(username: 'aziz');
    expect(adapter.requests.last.data, {'username': 'aziz'});
  });

  test('only the changed settings are sent', () async {
    serve({
      'PUT /api/social/settings': (_) => {
        'visibility': 'friends',
        'shareActivity': true,
        'allowRequests': 'everyone',
      },
    });
    final s = await remote.updateSettings(shareActivity: true);
    expect(adapter.requests.single.data, {'shareActivity': true});
    expect(s.shareActivity, isTrue);

    await remote.updateSettings(visibility: ProfileVisibility.private);
    expect(adapter.requests.last.data, {'visibility': 'private'});
  });

  group('errors', () {
    Future<SocialError> kindOf(int status, Map<String, dynamic> body) async {
      serve({'POST /api/social/requests': (_) => (status, body)});
      try {
        await remote.sendRequest(userId: 'u1');
      } on SocialException catch (e) {
        return e.kind;
      }
      fail('no exception');
    }

    test('server codes win over the status', () async {
      expect(
        await kindOf(403, {'message': 'x', 'code': 'REQUESTS_CLOSED'}),
        SocialError.requestsClosed,
      );
      expect(
        await kindOf(409, {'message': 'x', 'code': 'ALREADY_FRIENDS'}),
        SocialError.alreadyFriends,
      );
      expect(
        await kindOf(409, {'message': 'x', 'code': 'FRIEND_LIMIT'}),
        SocialError.friendLimit,
      );
      expect(
        await kindOf(429, {'message': 'x', 'code': 'TOO_MANY_PENDING'}),
        SocialError.tooManyPending,
      );
    });

    test('without a code the status decides', () async {
      expect(await kindOf(429, {'message': 'x'}), SocialError.rateLimited);
      expect(await kindOf(404, {'message': 'x'}), SocialError.notFound);
      expect(await kindOf(401, {'message': 'x'}), SocialError.unauthorized);
      expect(await kindOf(500, {'message': 'x'}), SocialError.unknown);
    });

    test('hidden activity is its own error', () async {
      serve({
        'GET /api/social/users/aziz/activity': (_) =>
            (403, {'message': 'Faoliyat yopiq', 'code': 'ACTIVITY_HIDDEN'}),
      });
      expect(
        () => remote.userActivity('aziz'),
        throwsA(
          isA<SocialException>().having(
            (e) => e.kind,
            'kind',
            SocialError.activityHidden,
          ),
        ),
      );
    });
  });
}
