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
import 'package:soplay/features/extensions/presentation/repo_file_import.dart';
import 'package:soplay/core/js/js_runtime_service.dart';
import 'package:soplay/core/player/media_controller.dart' show warmUpPlayerEngine;
import 'package:soplay/core/system/app_orientation.dart';
import 'package:soplay/core/js/provider_registry.dart';
import 'package:soplay/features/download/domain/repositories/download_repository.dart';
import 'package:soplay/features/notifications/data/services/notification_service.dart';

import 'package:soplay/core/network/user_agent.dart';
import 'app.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
    final native = Hive.box(AppConstants.settingsBox)
        .get('use_native_title_bar', defaultValue: false) == true;
    try {
      await windowManager.setTitleBarStyle(
        native ? TitleBarStyle.normal : TitleBarStyle.hidden,
           windowButtonVisibility: Platform.isMacOS ? true : native,
      );
      await windowManager.setMinimumSize(const Size(800, 560));
    } catch (_) {}
    DesktopWindow.nativeTitleBar.value = native;
  }

  PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
  await _initFirebaseSafely();
  await configureDependencies();
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
    ],
    path: 'assets/translations',
    fallbackLocale: const Locale('en'),
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
  });
}

Future<void> _initHive() async {
  if (isDesktopPlatform) {
    final dir = await getApplicationSupportDirectory();
    Hive.init(dir.path);
  } else {
    await Hive.initFlutter();
  }
  await Future.wait([

    Hive.openBox(AppConstants.authBox),
    Hive.openBox(AppConstants.settingsBox),
    Hive.openBox(AppConstants.historyBox),
    Hive.openBox(AppConstants.downloadBox),
    Hive.openBox(AppConstants.extractorsBox),
    Hive.openBox(AppConstants.streakBox),
    Hive.openBox(AppConstants.favoritesBox),
    Hive.openBox(AppConstants.userListsBox),
    Hive.openBox(AppConstants.privateFavoritesBox),
  ]);
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
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (e) {
    if (kDebugMode) debugPrint('[Firebase] init failed: $e');
  }
}
