import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'package:soplay/core/router/app_router.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';
import 'package:soplay/features/streak/data/streak_service.dart';

/// Keeps the Android home screen widgets in step with the app.
///
/// The widgets draw a snapshot and nothing else, so everything they show is
/// decided here: the three titles Home would offer to continue, in the
/// viewer's language; their posters, fetched and shrunk to files the widget
/// can read; the streak; and the next episode due from the viewer's AniList
/// list. Anything that changes with the clock — the countdown, whether the
/// streak is at risk tonight — is left to the widget, which redraws without
/// the app.
class HomeWidgetSync with WidgetsBindingObserver {
  HomeWidgetSync({
    required HistoryService history,
    required StreakService streak,
    required HiveService hive,
    AnilistService? anilist,
    Dio? dio,
  }) : _history = history,
       _streak = streak,
       _hive = hive,
       _anilist = anilist,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 15),
               responseType: ResponseType.bytes,
             ),
           );

  final HistoryService _history;
  final StreakService _streak;
  final HiveService _hive;
  final AnilistService? _anilist;
  final Dio _dio;

  static const MethodChannel _channel = MethodChannel('sozo/home_widget');

  static bool get supported => !kIsWeb && Platform.isAndroid && !isTvPlatform;

  /// How many titles the widgets can show.
  static const int _slots = 3;

  Timer? _debounce;
  bool _started = false;

  void start() {
    if (!supported || _started) return;
    _started = true;
    _history.revision.addListener(_soon);
    _streak.state.addListener(_soon);
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'action' && call.arguments is Map) {
        _handle((call.arguments as Map).cast<String, dynamic>());
      }
      return null;
    });
    _takeLaunchAction();
    _soon();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving the app is when the widget is looked at next: whatever changed
    // in this session — a lock just turned on, an episode just finished —
    // should be on the home screen by then.
    if (state == AppLifecycleState.paused) unawaited(push());
  }

  void _soon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => unawaited(push()));
  }

  bool _pushing = false;

  Future<void> push() async {
    if (!supported || _pushing) return;
    _pushing = true;
    try {
      final snapshot = await _snapshot();
      await _channel.invokeMethod('update', jsonEncode(snapshot));
    } catch (e) {
      debugPrint('[home_widget] update failed: $e');
    } finally {
      _pushing = false;
    }
  }

  // --- the snapshot ----------------------------------------------------------

  Future<Map<String, dynamic>> _snapshot() async {
    final labels = {
      'continue': 'home.continue_watching'.tr(),
      'next': 'home_widget.next'.tr(),
      'outNow': 'home_widget.out_now'.tr(),
      'locked': 'home_widget.locked'.tr(),
      'lockedHint': 'home_widget.locked_hint'.tr(),
      'atRisk': 'home_widget.at_risk'.tr(),
      'empty': 'home_widget.empty'.tr(),
      'days': 'home_widget.days'.tr(),
    };
    // A locked app shows nothing of what was watched — not on the lock
    // screen's doorstep, the home screen.
    if (_hive.isAppLockEnabled) {
      await _prunePosters(const {});
      return {'locked': true, 'labels': labels};
    }
    final items = continueItems(_history.getAll());
    final posters = <String>{};
    final rows = <Map<String, dynamic>>[];
    for (final item in items) {
      final path = await _poster(item.thumbnail);
      if (path != null) posters.add(path);
      rows.add({
        'title': item.title,
        'subtitle': subtitleOf(item),
        'progress': item.progress,
        'poster': ?path,
        'contentUrl': item.contentUrl,
        'provider': item.provider,
        'episodeIndex': ?item.episodeIndex,
      });
    }
    await _prunePosters(posters);
    final streak = _streak.state.value;
    return {
      'locked': false,
      'labels': labels,
      'items': rows,
      if (_hive.isLoggedIn && streak.current > 0)
        'streak': {
          'current': streak.current,
          'lastActiveDate': ?streak.lastActiveDate,
        },
      'next': ?await _nextAiring(),
    };
  }

  /// The titles Home offers to continue, newest first: one row per title,
  /// finished films left out — the same rule as the Continue watching rail.
  @visibleForTesting
  static List<HistoryItem> continueItems(List<HistoryItem> all) {
    final byContent = <String, HistoryItem>{};
    for (final item in all) {
      if (item.contentUrl.isEmpty) continue;
      if (item.progress >= 0.95 && !item.isSerial) continue;
      final had = byContent[item.contentUrl];
      if (had == null || item.watchedAt > had.watchedAt) {
        byContent[item.contentUrl] = item;
      }
    }
    final out = byContent.values.toList()
      ..sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
    return out.take(_slots).toList();
  }

  /// "Episode 7 · 14 min left", "Chapter 128".
  @visibleForTesting
  static String subtitleOf(HistoryItem item) {
    final reading = item.mediaType == 'manga' || item.mediaType == 'novel';
    final label = item.episodeLabel?.trim();
    final number = item.episodeNumber ?? item.episodeIndex;
    final unit = !item.isSerial
        ? null
        : (label != null && label.isNotEmpty && int.tryParse(label) == null)
        ? label
        : number == null
        ? null
        : (reading ? 'home_widget.chapter' : 'home_widget.episode').tr(
            args: ['$number'],
          );
    final left = !reading && item.durationMs > 0
        ? ((item.durationMs - item.positionMs) / 60000).ceil()
        : 0;
    return [
      ?unit,
      if (left > 0 && item.progress < 0.95)
        'home_widget.min_left'.tr(args: ['$left']),
    ].join(' · ');
  }

  // --- posters ---------------------------------------------------------------

  Directory? _dir;

  Future<Directory> _posterDir() async {
    final cached = _dir;
    if (cached != null) return cached;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/home_widget');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  /// A poster the widget can read: fetched once per image, shrunk to the
  /// largest size a widget draws it, kept until it leaves the snapshot.
  Future<String?> _poster(String? url) async {
    if (url == null || !url.startsWith('http')) return null;
    try {
      final dir = await _posterDir();
      final name = '${md5.convert(utf8.encode(url))}.png';
      final file = File('${dir.path}/$name');
      if (await file.exists()) return file.path;
      final res = await _dio.get<List<int>>(url);
      final bytes = res.data;
      if (bytes == null || bytes.isEmpty) return null;
      final codec = await ui.instantiateImageCodec(
        Uint8List.fromList(bytes),
        targetWidth: 360,
      );
      final frame = await codec.getNextFrame();
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      if (png == null) return null;
      await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
      return file.path;
    } catch (e) {
      debugPrint('[home_widget] poster failed: $e');
      return null;
    }
  }

  Future<void> _prunePosters(Set<String> keep) async {
    try {
      final dir = await _posterDir();
      await for (final f in dir.list()) {
        if (f is File && !keep.contains(f.path)) await f.delete();
      }
    } catch (_) {}
  }

  // --- the next episode ------------------------------------------------------

  Map<String, dynamic>? _nextCache;
  DateTime? _nextAt;

  /// The soonest episode due from the viewer's AniList list, or the one that
  /// went out within the day. Asked of AniList at most every few hours.
  Future<Map<String, dynamic>?> _nextAiring() async {
    final anilist = _anilist;
    if (anilist == null || !anilist.isConnected) return null;
    final at = _nextAt;
    if (at != null &&
        DateTime.now().difference(at) < const Duration(hours: 3)) {
      return _nextCache;
    }
    try {
      final entries = await anilist.library();
      final now = DateTime.now();
      ({DateTime at, String title, int episode})? best;
      for (final e in entries) {
        if (e.status != 'CURRENT' && e.status != 'REPEATING') continue;
        final airing = e.media.nextAiring;
        if (airing == null) continue;
        final airs = airing.airsAt;
        if (now.difference(airs) > const Duration(hours: 24)) continue;
        if (best == null || airs.isBefore(best.at)) {
          best = (
            at: airs,
            title: e.media.displayTitle,
            episode: airing.episode,
          );
        }
      }
      _nextAt = DateTime.now();
      _nextCache = best == null
          ? null
          : {
              'title': best.title,
              'episode': 'home_widget.episode'.tr(args: ['${best.episode}']),
              'airsAt': best.at.millisecondsSinceEpoch,
            };
      return _nextCache;
    } catch (e) {
      debugPrint('[home_widget] next airing failed: $e');
      return _nextCache;
    }
  }

  // --- taps ------------------------------------------------------------------

  Future<void> _takeLaunchAction() async {
    try {
      final raw = await _channel.invokeMethod<Map>('takeLaunchAction');
      if (raw != null) _handle(raw.cast<String, dynamic>());
    } catch (_) {}
  }

  /// Opens what a widget tap asked for — once Home is up, since a page pushed
  /// over the splash is swept away when the splash hands over to Home.
  void _handle(Map<String, dynamic> action) {
    void go() {
      switch (action['action']) {
        case 'continue':
          final url = action['contentUrl'] as String?;
          if (url == null || url.isEmpty) return;
          AppRouter.router.push(
            '/detail',
            extra: DetailArgs(
              contentUrl: url,
              autoPlay: true,
              resumeEpisodeIndex: action['episodeIndex'] as int?,
              provider: action['provider'] as String?,
            ),
          );
        case 'next':
          AppRouter.router.push('/anilist/calendar');
      }
    }

    final delegate = AppRouter.router.routerDelegate;
    bool atHome() {
      final path = delegate.currentConfiguration.uri.path;
      return path.isNotEmpty && path != '/splash' && path != '/onboarding';
    }

    if (atHome()) {
      go();
      return;
    }
    late VoidCallback listener;
    listener = () {
      if (!atHome()) return;
      delegate.removeListener(listener);
      WidgetsBinding.instance.addPostFrameCallback((_) => go());
    };
    delegate.addListener(listener);
  }
}
