import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:soplay/core/analytics/analytics.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/extensions/extension_bridge.dart';
import 'package:soplay/core/storage/box_recovery.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/anilist/data/airing_reminders.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/mal/data/mal_service.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/system/whats_new.dart';
import 'package:soplay/core/system/desktop_window.dart';
import 'package:soplay/core/deeplink/deeplink_service.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/router/app_router.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';
import 'package:soplay/features/extensions/presentation/repo_file_import.dart';
import 'package:soplay/core/js/js_runtime_service.dart';
import 'package:soplay/core/player/media_controller.dart'
    show warmUpPlayerEngine;
import 'package:soplay/core/system/app_orientation.dart';
import 'package:soplay/core/js/provider_registry.dart';
import 'package:soplay/features/download/domain/repositories/download_repository.dart';
import 'package:soplay/core/brand/sozo_mark_geometry.dart';
import 'package:soplay/features/notifications/data/services/notification_service.dart';

import 'package:soplay/core/network/user_agent.dart';
import 'package:soplay/core/storage/profile_storage.dart';
import 'package:soplay/core/storage/secure_boxes.dart';
import 'package:soplay/features/profiles/data/profile_session.dart';
import 'package:soplay/features/app_lock/presentation/app_lock_gate.dart';
import 'app.dart';

/// [args] is what the OS handed the process, and on Windows and Linux that is
/// how "Open with Sozo" arrives: both runners hand `argv` to the engine as the
/// Dart entrypoint arguments, so the file the user double-clicked was reaching
/// Dart and being dropped by an entrypoint that took no parameters.
///
/// macOS is NOT covered. Its runner has no equivalent call, and AppKit does not
/// put opened files in `argv` at all — it delivers them to
/// `NSApplicationDelegate application(_:open:)` after launch. So a file opened
/// with Sozo on macOS still goes nowhere; wiring that up is a change in
/// `macos/Runner/`, not here. Android and iOS never pass anything, so the list
/// is simply empty there.
void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Started first and awaited last. The splash needs the mark's geometry AND
  // its artwork decoded before its first frame, and the artwork is a 1024px
  // image; begun here it decodes while Hive, DI and the rest of startup run,
  // instead of adding its own time on top of theirs.
  final brand = SozoMarkGeometry.precache();
  await initTvPlatform();
  if (isDesktopPlatform) {
    MediaKit.ensureInitialized();
    await windowManager.ensureInitialized();
  }
  // Not `isMobilePlatform`: on iOS 26 the bar is a real UITabBar, so compiling
  // a GLSL glass pipeline is cost with nothing to show for it.
  if (usesFlutterGlass) {
    try {
      await LiquidGlassWidgets.initialize();
    } catch (_) {}
  }
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {}
  await Future.wait([
    EasyLocalization.ensureInitialized(),
    _initHive(),
    // Adopt the device's own WebView User-Agent before anything makes a
    // request. A Cloudflare managed challenge compares the header against the
    // engine behind it, so a hard-coded version that does not match this
    // device's WebView is a mismatch the challenge never clears.
    initSozoUserAgent(),
  ]);
  // After Hive, before the first frame: it reads and may stamp a settings key,
  // and a first run must be stamped before anything can be called new.
  await WhatsNew.init();
  if (isDesktopPlatform) {
    final native =
        Hive.box(
          AppConstants.settingsBox,
        ).get('use_native_title_bar', defaultValue: false) ==
        true;
    try {
      await windowManager.setTitleBarStyle(
        native ? TitleBarStyle.normal : TitleBarStyle.hidden,
        windowButtonVisibility: Platform.isMacOS ? true : native,
      );
      await windowManager.setMinimumSize(DesktopWindow.minimumSize);
    } catch (_) {}
    DesktopWindow.nativeTitleBar.value = native;
    // Geometry first, listener second: restoring fires resize and move events
    // of its own, and there is nothing to learn from the app moving its own
    // window back to where the user already put it.
    await DesktopWindow.restoreGeometry();
    DesktopWindow.trackWindow();
  }

  PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
  await _initFirebaseSafely();
  await configureDependencies();
  // Before anything can navigate — the deep-link and push handlers below, and
  // the first frame — so every way in lands under the lock.
  getIt<AppLockGate>().start();
  // Resolved here, opened after the first frame. What it needs from this point
  // in startup is the dependency graph — the player reads history, settings and
  // the engine preference out of it — but pushing a route before there is a
  // Navigator to push onto is a different question, which is why the actual
  // navigation waits for the post-frame callback at the bottom of this
  // function. Resolving it now also means a file that does not exist costs
  // nothing later.
  final launchFile = isDesktopPlatform ? _playableLaunchArg(args) : null;
  if (!Platform.isAndroid) {
    ExtensionBridge.setUrl(getIt<HiveService>().getBridgeUrl());
  }
  // After the graph exists, and off the critical path: nothing on screen waits
  // on it, and whether it may send at all is a Hive setting that had to be
  // open first.
  _fireAndForget(
    getIt<Analytics>().start().then((live) {
      if (live) getIt<Analytics>().track(AnalyticsEvent.appOpened);
    }),
    'analytics',
  );
  // Storage root, integrity sweep, then whatever was interrupted. Off the
  // critical path: it walks the downloads folder, and nothing on screen waits
  // for it — but it has to run before the Downloads screen can be trusted,
  // which is why it is here rather than in that screen's initState.
  _fireAndForget(
    getIt<DownloadRepository>().initialize().then(
      (_) => getIt<DownloadRepository>().resumeInterrupted(),
    ),
    'download',
  );
  _fireAndForget(getIt<ProviderRegistry>().preload(), 'providers');
  // setup(), not just ensureInitialized(): registering the device is what makes
  // it reachable, and it belongs to opening the app rather than to signing in.
  _fireAndForget(getIt<NotificationService>().setup(), 'fcm');
  _fireAndForget(getIt<DeeplinkService>().start(), 'deeplink');
  _fireAndForget(_restoreAnilistAndReminders(), 'anilist');
  RepoFileImport.start(
    () => AppRouter.router.routerDelegate.navigatorKey.currentContext,
  );
  unawaited(
    AppOrientation.set([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]).catchError((Object _) {}),
  );
  unawaited(
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    ).catchError((Object _) {}),
  );
  Widget root = EasyLocalization(
    supportedLocales: const [
      Locale('en'),
      Locale('uz'),
      Locale('ru'),
      // Arabic reads right-to-left. Flutter mirrors the framework's own
      // widgets — Row, ListView, Drawer, back buttons — off the locale alone;
      // what it cannot mirror is a hard-coded `EdgeInsets.only(left:)`, so the
      // app's own chrome was converted to the directional forms alongside this.
      // Deliberately not mirrored: the player's brightness/volume swipe zones
      // and its seek bar, which are physical geometry rather than reading
      // order and read the same in every language.
      Locale('ar'),
      // Latin-script tier. Nothing here needs a bundled font or a mirrored
      // layout: the app ships no custom font, so the system one covers them,
      // and every one of them reads left to right like English does.
      Locale('de'),
      Locale('nl'),
      Locale('es'),
      // `pt`, not `pt-BR`, though the copy is written in Brazilian Portuguese.
      // A region tag would have been the only two-part code in the set — a
      // special case in the file names, in the check script, and in
      // `kSubtitleTranslateLanguages`, which lists plain `pt` and would have
      // silently dropped a `pt-BR` reader back to the default target language.
      Locale('pt'),
      Locale('fr'),
      Locale('tr'),
      Locale('id'),
      // Cantonese, in Traditional characters. `yue` rather than `zh-HK`
      // because the copy is written in Cantonese — 睇, 嘅, 冇 — and not in the
      // Standard Written Chinese a `zh` tag promises; a reader who set their
      // phone to Mandarin should not land here by a region match.
      Locale('yue'),
    ],
    path: 'assets/translations',
    fallbackLocale: const Locale('en'),
    // Without this a key missing from one locale renders as the key itself —
    // the user reads `profile.language_desc` where a sentence belongs. CI gates
    // on the key check, so this should never fire; it is here because the day
    // it does, English is a far better answer than raw dot-notation.
    useFallbackTranslations: true,
    child: const MyApp(),
  );
  if (usesFlutterGlass) {
    // Adaptive glass quality (auto-degrades to a plain frosted tier on weak /
    // non-Impeller GPUs) + app-wide glass theming hooks. Never runs on desktop,
    // and never on iOS 26, where the bar is a native UIKit material.
    //
    // The scope is left at its defaults on purpose. It starts at `premium` and
    // re-benchmarks after every resume, which would matter — except the nav bar
    // is the app's only glass widget and it now names `GlassQuality.standard`
    // explicitly, and an explicit widget quality wins over the scope's. Capping
    // the scope too would mean depending on `GlassAdaptiveScopeConfig`, which
    // the package marks experimental, to re-state something already decided at
    // the one call site that matters.
    root = LiquidGlassWidgets.wrap(child: root, adaptiveQuality: true);
  }
  // Before the first frame. The splash is the first thing this process draws
  // and it draws the mark from geometry and artwork, so both have to exist
  // when it starts rather than arrive alongside it. Started at the top of
  // `main`, so by here it has usually finished. Not awaited, exactly one
  // launch per install — the cold one everybody's first impression is made
  // of — would fall back to a flat logo.
  await brand;

  runApp(root);

  // Deferred to after the first frame on purpose.
  //
  // Both of these load a large native library on the platform thread the first
  // time they run — WebView pulls in libwebviewchromium.so (plus a sandboxed
  // renderer process), media_kit pulls in libmpv. Kicked off before runApp they
  // land squarely inside startup and show up as a ~1s dropped-frame stall
  // before the first screen is even painted. After the first frame the user is
  // looking at real UI while the same work happens.
  //
  // Still eager rather than on-demand: paying it here, once, is what keeps it
  // out of the player, where the same stall reads as "the video took a second
  // to open".
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _fireAndForget(getIt<JsRuntimeService>().ensureReady(), 'js');
    _fireAndForget(warmUpPlayerEngine(), 'player-engine');
    // `push`, not `go`: the shell stays underneath, so closing the file the app
    // was opened with leaves the user in the app rather than on a blank stack.
    if (launchFile != null) AppRouter.router.push('/player', extra: launchFile);
  });
}

/// Container formats libmpv plays and the OS is likely to hand us.
///
/// An allow-list rather than "anything that exists": the same argv carries
/// Flutter's own `--dart-entrypoint`-style switches and, on Linux, whatever a
/// desktop file or a shell glob felt like passing, and opening the player on
/// one of those would be worse than ignoring it.
const Set<String> _playableExtensions = {
  '.mkv',
  '.mp4',
  '.m4v',
  '.mov',
  '.avi',
  '.webm',
  '.wmv',
  '.flv',
  '.ts',
  '.m2ts',
  '.mpg',
  '.mpeg',
  '.ogv',
  '.3gp',
  '.m3u8',
  '.mp3',
  '.flac',
  '.aac',
  '.wav',
  '.ogg',
  '.opus',
  '.m4a',
};

/// `.ts` is the one extension in [_playableExtensions] that is far more often
/// TypeScript source than an MPEG transport stream. Registering Sozo as an
/// "Open with" handler, or a `sozo *.ts` glob in a source tree, would otherwise
/// be enough to open a video player on somebody's code.
///
/// So this extension alone has to corroborate itself from the bytes rather than
/// from the name. A transport stream is a run of fixed-length packets each
/// beginning with the sync byte 0x47 — 188 bytes for plain TS, 192 for the
/// timecode-prefixed variant — so three of those in a row at the same stride is
/// the format identifying itself. `G` at one offset is an accident a text file
/// can have; `G` at three offsets exactly one packet apart is not.
///
/// The leading offset is searched rather than assumed because captures and
/// partial downloads routinely start mid-packet.
bool _isTransportStream(String path) {
  const strides = [188, 192];
  RandomAccessFile? handle;
  try {
    handle = File(path).openSync();
    final head = handle.readSync(192 + 2 * 192 + 1);
    for (var start = 0; start < 192; start++) {
      for (final stride in strides) {
        final last = start + 2 * stride;
        if (last >= head.length) continue;
        if (head[start] == 0x47 &&
            head[start + stride] == 0x47 &&
            head[last] == 0x47) {
          return true;
        }
      }
    }
    return false;
  } catch (_) {
    // Unreadable is not playable either, so the answer is the same.
    return false;
  } finally {
    try {
      handle?.closeSync();
    } catch (_) {}
  }
}

/// The first launch argument that is a media file on disk, as the player's own
/// arguments — or null when the app was started normally.
PlayerArgs? _playableLaunchArg(List<String> args) {
  for (final raw in args) {
    final arg = raw.trim();
    if (arg.isEmpty || arg.startsWith('-')) continue;
    final path = _asLocalPath(arg);
    if (path == null) continue;
    final dot = path.lastIndexOf('.');
    if (dot < 0) continue;
    final extension = path.substring(dot).toLowerCase();
    if (!_playableExtensions.contains(extension)) continue;
    if (!File(path).existsSync()) continue;
    if (extension == '.ts' && !_isTransportStream(path)) continue;
    final isHls = extension == '.m3u8';
    return PlayerArgs(
      // The file name is the only title there is. Everything downstream keys
      // history and the trackers on the title/provider pair, so a local file
      // gets its own provider rather than borrowing an extension's.
      title: path.split(Platform.pathSeparator).last,
      provider: 'local',
      headers: const {},
      // A playlist has to go in as a URL for the HLS demuxer to resolve its
      // segment paths; a plain container is handed over as the path it is.
      movieUrl: isHls ? Uri.file(path).toString() : path,
      type: isHls ? 'hls' : null,
      // It is already on this machine.
      showDownloadAction: false,
    );
  }
  return null;
}

/// A launch argument read as a path on disk, or null when it is something else.
///
/// The scheme test has a length bound because `C:\films\ep1.mkv` parses as a
/// URI whose scheme is `c` — a one-letter scheme is a Windows drive, never a
/// protocol. Anything with a real scheme is a link rather than a file, and
/// `sozo://` and `https://` belong to DeeplinkService; claiming them here as
/// well would open the same link twice.
String? _asLocalPath(String arg) {
  final uri = Uri.tryParse(arg);
  if (uri == null || uri.scheme.length < 2) return arg;
  if (!uri.isScheme('file')) return null;
  try {
    return uri.toFilePath();
  } catch (_) {
    return null;
  }
}

/// Opens every box the app needs, and starts even when one of them will not.
///
/// The directory is resolved here rather than left to `Hive.initFlutter()` so
/// that [BoxRecovery] has somewhere to put a file it cannot read. It is the same
/// path that extension resolves to — the documents directory — so nothing on an
/// existing install moves.
Future<void> _initHive() async {
  final dir = isDesktopPlatform
      ? await getApplicationSupportDirectory()
      : await getApplicationDocumentsDirectory();
  Hive.init(dir.path);
  // The two boxes holding secrets — the session and tracker tokens, and the
  // PIN-hidden private list — open encrypted; see SecureBoxes. Its own fallback
  // already keeps a launch alive without losing the file, so the guard here is
  // only for the plain-text branch inside it.
  final cipher = await SecureBoxes.cipher();
  Future<Box<dynamic>> secure(String name) async {
    try {
      return await SecureBoxes.open(name, cipher);
    } catch (e) {
      debugPrint('[SecureBoxes] $name: unopenable, running in memory: $e');
      return Hive.openBox(name, bytes: Uint8List(0));
    }
  }

  // Every box on its own footing. One unreadable file used to take `main()`
  // down before `runApp` — a blank screen, no message, and the only way out was
  // clearing the app's data, which throws away the eight boxes that were fine
  // along with the one that was not. And Hive's default on a bad checksum is to
  // truncate the file to the last frame it could read, so the box that DID open
  // could come back silently emptier than the user left it; see [BoxRecovery].
  await Future.wait([
    secure(AppConstants.authBox),
    for (final name in const [
      AppConstants.settingsBox,
      AppConstants.historyBox,
      AppConstants.downloadBox,
      AppConstants.extractorsBox,
      AppConstants.streakBox,
      AppConstants.favoritesBox,
      AppConstants.userListsBox,
    ])
      BoxRecovery.open(name, directory: dir.path),
    secure(AppConstants.privateFavoritesBox),
  ]);
  ProfileStorage.directory = dir.path;
  final token = Hive.box(AppConstants.authBox).get(AppConstants.accessTokenKey);
  await ProfileSession.restore(
    Hive.box(AppConstants.settingsBox),
    loggedIn: token is String && token.isNotEmpty,
  );
}

/// Restores the tracker links, then lays down the next window of episode
/// reminders.
///
/// The schedule used to be refreshed only while the airing calendar was on
/// screen, so someone who turned reminders on and never opened that page again
/// stopped being told anything once the first week ran out. Startup is where
/// this belongs: it is the one moment the app is guaranteed to reach.
Future<void> _restoreAnilistAndReminders() async {
  final anilist = getIt<AnilistService>();
  await anilist.restore();
  // Restored in the same breath, and its failures are just as swallowed: a
  // tracker that cannot be reached at startup must not hold up the app.
  unawaited(getIt<MalService>().restore().catchError((Object _) {}));
  final reminders = getIt<AiringReminders>();
  if (!reminders.enabled || !anilist.isConnected) return;
  await reminders.sync(await anilist.library());
}

void _fireAndForget(Future<void> future, String tag) {
  future.catchError((Object e) {
    if (kDebugMode) debugPrint('[$tag] background init failed: $e');
  });
}

Future<void> _initFirebaseSafely() async {
  if (!Platform.isAndroid) return;
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      !kDebugMode,
    );
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (e) {
    if (kDebugMode) debugPrint('[Firebase] init failed: $e');
  }
}
