import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/discord/discord_activity.dart';

void main() {
  DiscordActivity make({
    String title = 'Demon Slayer',
    String? subtitle = 'S4 · E8',
    String? image = 'https://img/1.jpg',
    String? url = 'https://sozo/x',
    DateTime? started,
  }) => DiscordActivity(
    title: title,
    subtitle: subtitle,
    imageUrl: image,
    imageText: 'HDHub4u',
    watchUrl: url,
    startedAt: started,
  );

  group('sameAs', () {
    test('ignores the clock', () {
      // The whole point. A player ticks several times a second and Discord
      // drops presence updates sent more often than roughly one every fifteen
      // seconds — so comparing timestamps would mean every tick looked like a
      // change and almost every update was thrown away by Discord.
      final a = make(started: DateTime(2026, 1, 1, 12, 0, 0));
      final b = make(started: DateTime(2026, 1, 1, 12, 30, 0));
      expect(a.sameAs(b), isTrue);
    });

    test('catches an episode change', () {
      expect(make(subtitle: 'S4 · E8').sameAs(make(subtitle: 'S4 · E9')), isFalse);
    });

    test('catches a title change', () {
      expect(make(title: 'Naruto').sameAs(make(title: 'Bleach')), isFalse);
    });

    test('catches artwork and link changes', () {
      expect(make(image: 'a').sameAs(make(image: 'b')), isFalse);
      expect(make(url: 'a').sameAs(make(url: 'b')), isFalse);
    });

    test('null is never the same as something', () {
      // Stopping playback has to reach Discord, or a profile keeps saying
      // somebody is watching a film they closed an hour ago.
      expect(make().sameAs(null), isFalse);
    });

    test('a missing subtitle is a difference, not a match', () {
      // A film has no episode line; a series does. Moving between them is a
      // change worth sending.
      expect(make(subtitle: null).sameAs(make(subtitle: 'S1 · E1')), isFalse);
    });
  });

  group('copyWith', () {
    test('replaces only the times', () {
      final base = make(started: DateTime(2026, 1, 1));
      final moved = base.copyWith(startedAt: DateTime(2026, 2, 2));
      expect(moved.startedAt, DateTime(2026, 2, 2));
      expect(moved.title, base.title);
      expect(moved.subtitle, base.subtitle);
      expect(moved.watchUrl, base.watchUrl);
      // And the result still compares equal, because the clock is not part of
      // the comparison.
      expect(moved.sameAs(base), isTrue);
    });
  });
}
