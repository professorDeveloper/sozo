import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/system/star_prompt.dart';

void main() {
  StarPromptState finish(StarPromptState s, int episodes) {
    for (var i = 0; i < episodes; i++) {
      s = StarPromptRules.episodeCompleted(s);
    }
    return s;
  }

  group('StarPromptRules', () {
    test('stays hidden before the seventh finished episode', () {
      final s = finish(const StarPromptState(), 6);
      expect(s.completed, 6);
      expect(StarPromptRules.shouldShow(s), isFalse);
    });

    test('shows at seven', () {
      expect(
        StarPromptRules.shouldShow(finish(const StarPromptState(), 7)),
        isTrue,
      );
    });

    test('showing it snoozes it, so it shows once per threshold', () {
      final s = StarPromptRules.shown(finish(const StarPromptState(), 7));
      expect(StarPromptRules.shouldShow(s), isFalse);
      expect(s.nextAt, 27);
    });

    test('Later waits for twenty more episodes', () {
      var s = StarPromptRules.later(finish(const StarPromptState(), 9));
      s = finish(s, 19);
      expect(StarPromptRules.shouldShow(s), isFalse);
      s = finish(s, 1);
      expect(s.completed, 29);
      expect(StarPromptRules.shouldShow(s), isTrue);
    });

    test('answering is final', () {
      var s = StarPromptRules.answered(finish(const StarPromptState(), 7));
      expect(StarPromptRules.shouldShow(s), isFalse);
      s = finish(s, 500);
      expect(StarPromptRules.shouldShow(s), isFalse);
      expect(StarPromptRules.shouldShow(StarPromptRules.later(s)), isFalse);
    });

    test('answering before the threshold also prevents it', () {
      final s = finish(StarPromptRules.answered(const StarPromptState()), 7);
      expect(StarPromptRules.shouldShow(s), isFalse);
    });
  });

  group('StarPromptState storage', () {
    test('round-trips through a map', () {
      const s = StarPromptState(completed: 12, nextAt: 31, done: true);
      expect(StarPromptState.fromMap(s.toMap()), s);
    });

    test('anything unreadable starts from scratch', () {
      expect(StarPromptState.fromMap(null), const StarPromptState());
      expect(StarPromptState.fromMap('x'), const StarPromptState());
      expect(
        StarPromptState.fromMap({'completed': 'a', 'done': 'yes'}),
        const StarPromptState(),
      );
    });
  });
}
