import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/js/dart_fetch.dart';
import 'package:soplay/core/js/extractor_cache.dart';
import 'package:soplay/core/js/extractor_remote.dart';
import 'package:soplay/core/js/js_runtime_service.dart';
import 'package:soplay/core/js/provider_registry.dart';
import 'package:soplay/core/manga/manga_channel.dart';
import 'package:soplay/core/network/certificate_pinning.dart';
import 'package:soplay/core/network/cf_bypass_service.dart';
import 'package:soplay/core/network/provider_interceptor.dart';
import 'package:soplay/features/detail/data/models/playback_model.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/notifications/data/notification_actions.dart';
import 'package:soplay/features/notifications/data/release_notifier.dart';
import 'package:soplay/features/profile/data/datasources/provider_data_source.dart';
import 'package:soplay/features/tracker/data/follow_service.dart';
import 'package:soplay/features/tracker/data/release_inbox.dart';

const String releaseWatchTask = 'sozo.release-check';

/// The WorkManager entry point. Runs in an engine of its own, with no DI, no
/// Hive and no Activity — see [ReleaseWorker].
@pragma('vm:entry-point')
void releaseWatchDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      await ReleaseWorker().run();
    } catch (e) {
      if (kDebugMode) debugPrint('[release-worker] failed: $e');
    }
    // Always "done": a failed check is retried by the next period, and a
    // retry storm from WorkManager's backoff would cost more than it finds.
    return true;
  });
}

/// One background pass over the titles the app asked to be watched.
///
/// Reads the snapshot the app wrote, asks each source for its newest episode,
/// posts what it learned to the inbox for the app to fold in, and raises a
/// notification for anything new the user wants to hear about.
class ReleaseWorker {
  ReleaseWorker({ReleaseInbox? inbox, EpisodeProbe? probe, DateTime Function()? now})
    : _inbox = inbox,
      _probe = probe,
      _now = now ?? DateTime.now;

  ReleaseInbox? _inbox;
  EpisodeProbe? _probe;
  final DateTime Function() _now;

  static const Duration deadline = Duration(minutes: 8);
  static const Duration perTitle = Duration(seconds: 25);

  /// Returns the releases found, for tests.
  Future<List<ReleaseEvent>> run({ReleaseNotifier? notifier}) async {
    DartPluginRegistrant.ensureInitialized();
    final inbox = _inbox ??= await ReleaseInbox.open();
    final snapshot = inbox.readSnapshot();
    if (snapshot == null || snapshot.titles.isEmpty) return const [];

    final probe = _probe ??= HeadlessEpisodeProbe(adult: snapshot.adult);
    final known = <String, int>{};
    for (final e in inbox.peek()) {
      if (e.kind != ReleaseEventKind.release) continue;
      if (e.episode > (known[e.key] ?? 0)) known[e.key] = e.episode;
    }

    final found = <ReleaseEvent>[];
    final shout = <ReleaseAlert>[];
    final queue = [...snapshot.titles];
    final stop = _now().add(deadline);

    Future<void> worker() async {
      while (queue.isNotEmpty && _now().isBefore(stop)) {
        final t = queue.removeAt(0);
        EpisodeEntity? newest;
        try {
          newest = await probe.newest(t.provider, t.contentUrl).timeout(perTitle);
        } catch (_) {
          continue;
        }
        if (newest == null || newest.episode <= 0) continue;
        final prior = t.count > (known[t.key] ?? 0) ? t.count : (known[t.key] ?? 0);
        final label = newest.label.trim().isEmpty ? null : newest.label.trim();
        if (prior <= 0) {
          await inbox.post(
            ReleaseEvent(
              kind: ReleaseEventKind.release,
              provider: t.provider,
              contentUrl: t.contentUrl,
              mode: t.mode,
              episode: newest.episode,
              label: label,
              at: _now().millisecondsSinceEpoch,
              seedOnly: true,
              scope: snapshot.scope,
            ),
          );
          continue;
        }
        if (newest.episode <= prior) continue;
        final event = ReleaseEvent(
          kind: ReleaseEventKind.release,
          provider: t.provider,
          contentUrl: t.contentUrl,
          title: t.title,
          thumbnail: t.thumbnail,
          mode: t.mode,
          episode: newest.episode,
          fromEpisode: prior + 1,
          label: label,
          at: _now().millisecondsSinceEpoch,
          scope: snapshot.scope,
        );
        await inbox.post(event);
        found.add(event);
        if (t.notify) {
          shout.add(
            ReleaseAlert(
              provider: t.provider,
              contentUrl: t.contentUrl,
              title: t.title,
              thumbnail: t.thumbnail,
              mode: t.mode,
              episodeNumber: newest.episode,
              episodeLabel: label,
              count: newest.episode - prior,
            ),
          );
        }
      }
    }

    try {
      await Future.wait([for (var i = 0; i < 3; i++) worker()]);
    } finally {
      await probe.close();
    }

    // Quiet hours hold local notifications back entirely; the feed still has
    // every one of them when the app is next opened.
    final prefs = snapshot.prefs;
    if (shout.isEmpty ||
        !prefs.allows('new_release') ||
        prefs.quiet.contains(_now())) {
      return found;
    }
    final n = notifier ?? await _notifier(snapshot);
    for (final alert in shout) {
      try {
        await n.showRelease(alert, snapshot.labels);
      } catch (e) {
        if (kDebugMode) debugPrint('[release-worker] notify failed: $e');
      }
    }
    return found;
  }

  static Future<ReleaseNotifier> _notifier(ReleaseWatchSnapshot snapshot) async {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings(ReleaseNotifier.smallIcon),
      ),
      onDidReceiveBackgroundNotificationResponse: onBackgroundNotificationAction,
    );
    final notifier = ReleaseNotifier(plugin);
    await notifier.ensureChannels(snapshot.labels);
    return notifier;
  }
}

/// Asks one source for its newest episode.
abstract class EpisodeProbe {
  Future<EpisodeEntity?> newest(String provider, String contentUrl);
  Future<void> close();
}

/// [EpisodeProbe] for an engine with no app around it.
///
/// Reaches what can be reached from here: the backend's providers over HTTP,
/// and the JS providers through a headless WebView. The Kotlin extension
/// hosts (`cs:`, `an:`, `mn:`) register their channels on the Activity's
/// engine, so they are probed once and skipped for the rest of the run when
/// they are not there. Mangayomi and Jellyfin live on state only the app
/// holds and are left to the foreground check.
class HeadlessEpisodeProbe implements EpisodeProbe {
  HeadlessEpisodeProbe({this.adult = false});

  final bool adult;

  late final Dio _dio = () {
    final dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          if (adult) ProviderInterceptor.adultHeader: '1',
        },
      ),
    );
    dio.httpClientAdapter = CertificatePinning.adapter();
    return dio;
  }();

  static const Map<String, String> _channels = {
    'cs:': 'soplay/cloudstream',
    'an:': 'soplay/aniyomi',
    'mn:': 'soplay/manga',
  };

  final Map<String, bool> _hostAvailable = {};
  JsRuntimeService? _js;
  bool _jsBroken = false;

  @override
  Future<EpisodeEntity?> newest(String provider, String contentUrl) async {
    if (provider.startsWith('my:') ||
        provider.startsWith('jf:') ||
        provider.startsWith('cat:')) {
      return null;
    }
    for (final entry in _channels.entries) {
      if (!provider.startsWith(entry.key)) continue;
      if (!await _hostUp(entry.key, entry.value)) return null;
      final id = provider.substring(3);
      final map = switch (entry.key) {
        'cs:' => await CloudStreamChannel.load(id, contentUrl),
        'an:' => await AniyomiChannel.load(id, contentUrl),
        _ => await MangaChannel.load(id, contentUrl),
      };
      return _newest(map);
    }

    final js = await _jsRuntime();
    if (js != null) {
      try {
        final map = await js.tryGetEpisodes(provider, contentUrl);
        if (map != null) return _newest(map);
      } catch (_) {}
    }
    final res = await _dio.get(
      '/contents/episodes',
      queryParameters: {
        'url': contentUrl,
        'page': 1,
        'size': 100,
        'sort': 'desc',
        'provider': provider,
      },
    );
    final data = res.data;
    return data is Map ? _newest(data.cast<String, dynamic>()) : null;
  }

  Future<bool> _hostUp(String prefix, String channel) async {
    final known = _hostAvailable[prefix];
    if (known != null) return known;
    var up = true;
    try {
      await MethodChannel(channel).invokeMethod<Object?>('listProviders');
    } on MissingPluginException {
      up = false;
    } catch (_) {
      // Registered and answering, just not happy with the question.
    }
    return _hostAvailable[prefix] = up;
  }

  Future<JsRuntimeService?> _jsRuntime() async {
    if (_jsBroken || !JsRuntimeService.isSupported) return null;
    final existing = _js;
    if (existing != null) return existing;
    try {
      await _openExtractorCache();
      final js = JsRuntimeService(
        remote: ExtractorRemote(dio: _dio),
        cache: ExtractorCache(),
        dartFetch: DartFetch.create(cfService: CfBypassService(), backendDio: _dio),
        providers: ProviderRegistry(source: ProviderDataSource(dio: _dio)),
      );
      await js.ensureReady().timeout(const Duration(seconds: 20));
      return _js = js;
    } catch (e) {
      if (kDebugMode) debugPrint('[release-worker] no JS runtime: $e');
      _jsBroken = true;
      return null;
    }
  }

  /// The extractor cache, as a private in-memory copy of the app's box. Hive
  /// must not open the real file from a second isolate.
  static Future<void> _openExtractorCache() async {
    if (Hive.isBoxOpen(AppConstants.extractorsBox)) return;
    Uint8List bytes = Uint8List(0);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${AppConstants.extractorsBox}.hive');
      if (file.existsSync()) bytes = await file.readAsBytes();
    } catch (_) {}
    try {
      await Hive.openBox(AppConstants.extractorsBox, bytes: bytes);
    } catch (_) {
      await Hive.openBox(AppConstants.extractorsBox, bytes: Uint8List(0));
    }
  }

  static EpisodeEntity? _newest(Map<String, dynamic> map) {
    if (map.isEmpty) return null;
    try {
      return FollowService.newestOf(PlaybackModel.fromJson(map).episodes);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> close() async {
    try {
      await _js?.dispose();
    } catch (_) {}
    _dio.close(force: true);
  }
}
