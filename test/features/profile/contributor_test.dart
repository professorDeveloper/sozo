import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/profile/domain/entities/contributor.dart';

void main() {
  group('Contributor.listFrom', () {
    test('reads the backend shape', () {
      final list = Contributor.listFrom({
        'contributors': [
          {
            'login': 'professorDeveloper',
            'avatarUrl': 'https://avatars.githubusercontent.com/u/1?v=4',
            'htmlUrl': 'https://github.com/professorDeveloper',
            'contributions': 252,
            'repos': ['sozo'],
          },
        ],
        'updatedAt': '2026-11-07T00:00:00Z',
      });
      expect(list, hasLength(1));
      expect(list.single.login, 'professorDeveloper');
      expect(list.single.contributions, 252);
    });

    test('accepts a bare list and skips rows without a login', () {
      final list = Contributor.listFrom([
        {'login': 'a'},
        {'login': ''},
        {'avatarUrl': 'https://x'},
        'junk',
        null,
      ]);
      expect(list.map((c) => c.login), ['a']);
      expect(list.single.htmlUrl, 'https://github.com/a');
      expect(list.single.avatarUrl, '');
      expect(list.single.contributions, 0);
    });

    test('only ever links to github.com', () {
      final c = Contributor.fromJson({
        'login': 'eve',
        'htmlUrl': 'https://evil.example/eve',
        'avatarUrl': 'http://insecure.example/a.png',
      })!;
      expect(c.htmlUrl, 'https://github.com/eve');
      expect(c.avatarUrl, '');
    });

    test('anything else is an empty list', () {
      expect(Contributor.listFrom(null), isEmpty);
      expect(Contributor.listFrom({'contributors': 'x'}), isEmpty);
    });

    test('survives its own cache format', () {
      final c = Contributor.fromJson({'login': 'a', 'contributions': 3})!;
      final back = Contributor.listFrom([c.toJson()]).single;
      expect(back.login, 'a');
      expect(back.contributions, 3);
    });
  });

  test('sizedAvatar keeps existing query and sets s', () {
    expect(
      Contributor.sizedAvatar('https://avatars.githubusercontent.com/u/1?v=4', 96),
      'https://avatars.githubusercontent.com/u/1?v=4&s=96',
    );
    expect(Contributor.sizedAvatar('', 96), '');
  });
}
