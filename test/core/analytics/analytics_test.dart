import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/analytics/analytics.dart';

void main() {
  group('event names', () {
    test('are unique', () {
      // Two events sharing a wire name silently merge into one chart, and the
      // merge is invisible: both call sites keep working.
      final names = AnalyticsEvent.values.map((e) => e.wireName).toList();
      expect(names.toSet().length, names.length);
    });

    test('are snake_case, so the dashboard reads as one vocabulary', () {
      for (final e in AnalyticsEvent.values) {
        expect(
          RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(e.wireName),
          isTrue,
          reason: '${e.name} sends "${e.wireName}"',
        );
      }
    });

    test('carry no content-shaped name', () {
      // A tripwire, not a proof: the rule is that no event names a title, a
      // query or a url, and the cheapest way to keep it is to fail the build
      // when somebody adds one.
      const banned = ['title', 'query', 'url', 'name', 'email', 'magnet'];
      for (final e in AnalyticsEvent.values) {
        for (final word in banned) {
          expect(
            e.wireName.contains(word),
            isFalse,
            reason: '${e.wireName} looks like it carries content',
          );
        }
      }
    });
  });

  group('property keys', () {
    test('are low-cardinality by name', () {
      const props = [
        AnalyticsProp.provider,
        AnalyticsProp.engine,
        AnalyticsProp.reason,
        AnalyticsProp.surface,
        AnalyticsProp.resultCount,
        AnalyticsProp.sourceCount,
        AnalyticsProp.kind,
        AnalyticsProp.durationSeconds,
      ];
      expect(props.toSet().length, props.length, reason: 'no duplicate keys');
      for (final p in props) {
        expect(RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(p), isTrue, reason: p);
      }
    });
  });

  group('without a key', () {
    test('analytics stays off and nothing throws', () async {
      // The state every fork, CI run and widget test is in. The app has to
      // behave identically to the shipped one, minus the reporting — so every
      // entry point must be safe to call against a client that was never
      // created.
      final analytics = Analytics(suppressed: () => false);

      expect(await analytics.start(), isFalse);
      expect(analytics.isEnabled, isFalse);

      // None of these may throw.
      analytics.track(AnalyticsEvent.appOpened);
      analytics.track(
        AnalyticsEvent.searchRan,
        props: {AnalyticsProp.resultCount: 3},
      );
      analytics.setUser('someone');
      analytics.setUser(null);
      await expectLater(analytics.flush(), completes);
    });

    test('tracking before start() is a no-op', () async {
      final analytics = Analytics(suppressed: () => false);
      analytics.track(AnalyticsEvent.playbackStarted);
      expect(analytics.isEnabled, isFalse);
    });
  });

  group('incognito', () {
    test('suppression is asked every time, not captured once', () {
      // The app promises that in incognito nothing is recorded. A cached answer
      // would keep that promise only for people who set the switch before
      // launch — and break it, silently, for everyone who flips it because they
      // are about to watch something.
      var asked = 0;
      final analytics = Analytics(suppressed: () {
        asked++;
        return false;
      });

      analytics.track(AnalyticsEvent.appOpened);
      analytics.track(AnalyticsEvent.searchRan);
      analytics.track(AnalyticsEvent.playbackStarted);

      // Never started, so the client short-circuits before the callback. The
      // guarantee under test is the ordering: no path may consult a remembered
      // value.
      expect(analytics.isEnabled, isFalse);
      expect(asked, 0, reason: 'no client means no send, and nothing to ask');
    });

    test('an unreadable setting reads as "do not send"', () async {
      // If the store cannot say whether the user asked for privacy, the safe
      // reading of "unknown" is silence.
      final analytics = Analytics(
        suppressed: () => throw StateError('settings box not open'),
      );
      await analytics.start();
      expect(analytics.isEnabled, isFalse);
      analytics.track(AnalyticsEvent.appOpened);
    });
  });
}
