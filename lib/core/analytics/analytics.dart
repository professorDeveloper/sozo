import 'dart:async';

import 'package:amplitude_flutter/amplitude.dart';
import 'package:amplitude_flutter/configuration.dart';
import 'package:amplitude_flutter/events/base_event.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:soplay/core/analytics/analytics_event.dart';

export 'package:soplay/core/analytics/analytics_event.dart';

/// Product analytics, and the rules it has to obey to be allowed near this app.
///
/// ## Incognito switches it off, completely
///
/// The app already promises that in incognito "nothing you watch is saved to
/// history or sent to AniList and MAL". An analytics SDK that kept sending
/// while that switch was on would make the promise false — and quietly, in the
/// one mode where somebody is explicitly asking not to be recorded. So
/// [isEnabled] reads the same flag the promise is made from, it is checked at
/// send time rather than at startup, and turning incognito on flushes nothing
/// pending: what has not left the device does not leave.
///
/// ## No content, ever
///
/// See [AnalyticsEvent]. Counts and outcomes, never titles, queries or urls.
///
/// ## Failure is silence
///
/// Every method swallows its errors. Analytics exists to inform a decision
/// later; nothing here is worth a crash, a delay, or a log line in front of a
/// user. A missing key is the normal case in a fork or a test run, and the app
/// must behave identically without it.
class Analytics {
  Analytics({required bool Function() suppressed, Amplitude? client})
      : _suppressed = suppressed,
        _client = client;

  static const String _envKey = 'AMPLITUDE_API_KEY';

  /// Whether the user has asked not to be recorded.
  ///
  /// A callback rather than the settings store itself, because "may I send?" is
  /// the entire dependency — taking the whole store would let this class reach
  /// for anything, and would make it untestable without opening Hive.
  final bool Function() _suppressed;
  Amplitude? _client;
  bool _started = false;

  /// Whether events may be sent right now.
  ///
  /// Recomputed per call rather than cached: incognito is a toggle someone
  /// flips mid-session, and the entire point is that it takes effect then, not
  /// at the next launch.
  bool get isEnabled {
    if (_client == null || !_started) return false;
    try {
      return !_suppressed();
    } catch (_) {
      // Hive unavailable means we cannot prove the user is not in incognito.
      // The safe reading of "unknown" is "do not send".
      return false;
    }
  }

  /// Brings the SDK up, or leaves it down.
  ///
  /// Awaited at startup but never blocking: the SDK's own init is local work,
  /// and the first flush happens on its own schedule. Returns whether analytics
  /// is live, which is only used by tests and diagnostics.
  Future<bool> start() async {
    if (_started) return _client != null;
    _started = true;

    // A build with no key is a valid build. Forks, CI runs and anyone working
    // from a clean checkout have none, and they must get an app that behaves
    // exactly like the shipped one minus the reporting.
    final key = _readKey();
    if (key == null) {
      debugPrint('[analytics] no $_envKey — analytics is off');
      _client = null;
      return false;
    }

    try {
      _client ??= Amplitude(
        Configuration(
          apiKey: key,
          // The SDK's own defaults collect an advertising id and location where
          // the platform allows it. Neither answers any question this app is
          // asking, and both are exactly the kind of thing a streaming app
          // should not be quietly gathering.
          enableCoppaControl: true,
        ),
      );
      await _client!.isBuilt;
      return true;
    } catch (e) {
      debugPrint('[analytics] could not start: $e');
      _client = null;
      return false;
    }
  }

  static String? _readKey() {
    try {
      final key = dotenv.env[_envKey]?.trim();
      return (key == null || key.isEmpty) ? null : key;
    } catch (_) {
      // dotenv throws when no .env was loaded, which is the normal state in a
      // widget test.
      return null;
    }
  }

  /// Records [event]. Never throws, never awaits anything the caller cares
  /// about, and does nothing at all in incognito.
  void track(AnalyticsEvent event, {Map<String, Object?> props = const {}}) {
    if (!isEnabled) return;
    try {
      unawaited(_client!.track(
        BaseEvent(
          event.wireName,
          eventProperties: {
            for (final e in props.entries)
              if (e.value != null) e.key: e.value!,
          },
        ),
      ));
    } catch (e) {
      debugPrint('[analytics] ${event.wireName} dropped: $e');
    }
  }

  /// Ties events to an account so a funnel can follow one person across their
  /// phone and their TV.
  ///
  /// Passing null on sign-out is the important half: without it the next
  /// person to use the device inherits the previous account's id.
  void setUser(String? userId) {
    if (_client == null || !_started) return;
    try {
      _client!.setUserId(userId);
    } catch (e) {
      debugPrint('[analytics] setUserId failed: $e');
    }
  }

  /// Sends whatever is queued. Called when the app goes to the background,
  /// which is where most sessions actually end.
  Future<void> flush() async {
    if (!isEnabled) return;
    try {
      await _client!.flush();
    } catch (e) {
      debugPrint('[analytics] flush failed: $e');
    }
  }
}
