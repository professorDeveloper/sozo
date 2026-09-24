import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/social/domain/social_models.dart';

void main() {
  group('SocialProfile', () {
    test('reads every field the server sends', () {
      final p = SocialProfile.fromJson({
        'user': {
          'id': 'u1',
          'username': 'aziz',
          'displayName': 'Aziz',
          'photoURL': 'https://img.test/a.png',
        },
        'relation': 'incoming',
        'requestId': 'r1',
        'friendsCount': 4,
        'canSeeActivity': true,
        'acceptsRequests': false,
      });
      expect(p.user.name, 'Aziz');
      expect(p.relation, SocialRelation.incoming);
      expect(p.requestId, 'r1');
      expect(p.friendsCount, 4);
      expect(p.canSeeActivity, isTrue);
      expect(p.acceptsRequests, isFalse);
    });

    test('a hidden count stays null and missing flags are safe', () {
      final p = SocialProfile.fromJson({
        'user': {'id': 'u1', 'username': 'aziz'},
        'relation': 'something-new',
        'friendsCount': null,
      });
      expect(p.friendsCount, isNull);
      expect(p.relation, SocialRelation.none);
      expect(p.canSeeActivity, isFalse);
      expect(p.acceptsRequests, isTrue);
      expect(p.user.name, 'aziz', reason: 'no display name falls back');
    });
  });

  test('an activity item parses its episode range and actor', () {
    final a = ActivityItem.fromJson({
      'id': 'a1',
      'type': 'read',
      'mediaType': 'manga',
      'provider': 'mn:x',
      'contentUrl': 'https://m.test/1',
      'episodeFrom': 3,
      'episodeTo': 7,
      'finished': true,
      'at': '2026-09-24T10:00:00.000Z',
      'actor': {'id': 'u2', 'username': 'bek'},
    });
    expect(a.type, ActivityType.read);
    expect(a.media, ActivityMedia.manga);
    expect(a.isReading, isTrue);
    expect(a.episodeFrom, 3);
    expect(a.episodeTo, 7);
    expect(a.finished, isTrue);
    expect(a.at, isNotNull);
    expect(a.actor?.username, 'bek');
    expect(a.canOpen, isTrue);
  });

  test('an activity with no content url cannot be opened', () {
    final a = ActivityItem.fromJson({'id': 'a1', 'provider': 'src'});
    expect(a.canOpen, isFalse);
    expect(a.type, ActivityType.unknown);
    expect(a.media, ActivityMedia.video);
  });

  test('a cursor page keeps the cursor and drops junk rows', () {
    final page = CursorPage.fromJson<FriendEntry>({
      'items': [
        {
          'user': {'id': 'u1', 'username': 'a'},
          'since': '2026-09-01T00:00:00Z',
        },
        'junk',
      ],
      'nextCursor': 'abc',
    }, FriendEntry.fromJson);
    expect(page.items, hasLength(1));
    expect(page.nextCursor, 'abc');

    final last = CursorPage.fromJson<FriendEntry>({
      'items': [],
      'nextCursor': null,
    }, FriendEntry.fromJson);
    expect(last.nextCursor, isNull);
  });

  test('settings default to private-by-default values', () {
    final s = SocialSettings.fromJson(const {});
    expect(s.shareActivity, isFalse);
    expect(s.visibility, ProfileVisibility.friends);
    expect(s.allowRequests, RequestPolicy.everyone);

    final t = SocialSettings.fromJson({
      'visibility': 'private',
      'shareActivity': true,
      'allowRequests': 'nobody',
    });
    expect(t.visibility, ProfileVisibility.private);
    expect(t.shareActivity, isTrue);
    expect(t.allowRequests, RequestPolicy.nobody);
  });

  test('a request knows its direction', () {
    final r = FriendRequest.fromJson({
      'id': 'r1',
      'direction': 'out',
      'user': {'id': 'u1', 'username': 'a'},
    });
    expect(r.incoming, isFalse);
  });
}
