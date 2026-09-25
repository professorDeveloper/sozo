import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/features/automation/data/auto_download_service.dart';
import 'package:soplay/features/tracker/data/follow_service.dart';

/// Checks followed titles for new episodes on a schedule, not only when the
/// Following page happens to be opened.
///
/// A new episode was found only by going to look for it: the check ran when
/// the page was opened, so the notification it can send arrived exactly when
/// it was no longer news. Now it runs by itself — when the app starts or comes
/// back to the foreground, if the chosen interval has passed since the last
/// check — in the background, with FollowService's own bounded concurrency and
/// per-title timeout, and notifies as it always has.
///
/// Foreground-driven rather than an OS background job on purpose: a real
/// background task needs a second engine with the whole app wired inside it,
/// for what is, for someone who opens the app daily, the same outcome.
class LibraryUpdateScheduler with WidgetsBindingObserver {
  LibraryUpdateScheduler({
    required this.follow,
    this.autoDownload,
    this.runCheck,
    Box? box,
    DateTime Function()? now,
  }) : _override = box,
       _now = now ?? DateTime.now;

  final FollowService follow;
  final AutoDownloadService? autoDownload;

  /// The check itself, when something above decides who announces what
  /// (ReleaseWatch). Without it, every grown title is announced.
  final Future<int> Function(AutoDownloadService? auto)? runCheck;
  final Box? _override;
  final DateTime Function() _now;

  Box get _box => _override ?? Hive.box(AppConstants.settingsBox);

  /// The choices offered, in hours; 0 is off. The same interval paces the
  /// background check, which Android will not run more often than every few
  /// hours anyway.
  static const List<int> choices = [0, 4, 6, 12, 24];
  static const int defaultHours = 6;

  Future<int>? _running;

  int get intervalHours {
    final v = _box.get(AppConstants.libraryUpdateHoursKey);
    return v is int && choices.contains(v) ? v : defaultHours;
  }

  Future<void> setIntervalHours(int hours) =>
      _box.put(AppConstants.libraryUpdateHoursKey, hours);

  DateTime? get lastCheckedAt {
    final v = _box.get(AppConstants.libraryUpdateLastKey);
    return v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
  }

  void start() {
    WidgetsBinding.instance.addObserver(this);
    // After the first frames, not during them: startup has enough to do.
    Timer(const Duration(seconds: 20), () => unawaited(maybeRun()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(maybeRun());
  }

  /// Whether a check is due now.
  @visibleForTesting
  bool get due {
    final hours = intervalHours;
    if (hours <= 0) return false;
    final last = lastCheckedAt;
    return last == null || _now().difference(last) >= Duration(hours: hours);
  }

  /// Runs a check if one is due. Calls while one is running join it.
  Future<int> maybeRun() {
    if (!due) return Future.value(0);
    return _running ??= _run().whenComplete(() => _running = null);
  }

  Future<int> _run() async {
    // Stamped first: a check that fails half way must not be retried on
    // every resume until it succeeds.
    await _box.put(
      AppConstants.libraryUpdateLastKey,
      _now().millisecondsSinceEpoch,
    );
    final auto = autoDownload;
    try {
      final check = runCheck;
      final grown = check != null
          ? await check(auto)
          : await follow.checkForUpdates(notify: true, onChecked: auto?.collect);
      if (auto != null) unawaited(auto.afterCheck());
      return grown;
    } catch (e) {
      debugPrint('[library-update] check failed: $e');
      return 0;
    }
  }
}
