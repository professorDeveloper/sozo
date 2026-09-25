import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/storage/profile_scope.dart';
import 'package:soplay/features/notifications/data/notification_actions.dart';
import 'package:soplay/features/notifications/data/notification_payload.dart';
import 'package:soplay/features/notifications/data/notification_prefs.dart';
import 'package:soplay/features/notifications/data/priming_cooldown.dart';
import 'package:soplay/features/notifications/data/release_notifier.dart';
import 'package:soplay/features/notifications/domain/repositories/notifications_repository.dart';
import 'package:soplay/features/social/data/social_service.dart';

typedef NotificationTapHandler = void Function(Map<String, dynamic> data);

class NotificationService {
  final NotificationsRepository repository;

  NotificationService({
    required this.repository,
    NotificationPrefsStore? prefs,
    PrimingCooldown? cooldown,
  }) : _prefs = prefs,
       _cooldown = cooldown;

  NotificationPrefsStore? _prefs;
  PrimingCooldown? _cooldown;

  NotificationPrefsStore get prefsStore => _prefs ??= NotificationPrefsStore();
  PrimingCooldown get cooldown => _cooldown ??= PrimingCooldown();
  NotificationPrefs get prefs => prefsStore.read();

  NotificationTapHandler? _onTap;

  /// A tap that arrived before [onTap] was wired (e.g. a cold-start invite tap
  /// routed via [FirebaseMessaging.getInitialMessage] during the auth flow,
  /// which runs before `MyApp` assigns [onTap]). Drained the moment a handler
  /// is assigned, so the tap is never lost.
  Map<String, dynamic>? _pendingTap;

  NotificationTapHandler? get onTap => _onTap;

  set onTap(NotificationTapHandler? handler) {
    _onTap = handler;
    final pending = _pendingTap;
    if (handler != null && pending != null) {
      _pendingTap = null;
      handler(pending);
    }
  }

  /// A release push that reached the running app, for the feed and the
  /// follow counts. Set by ReleaseWatch.
  Future<void> Function(ReleaseAlert alert, {String? profileId})? onReleasePush;

  /// "Mark seen" pressed on a release while the app is running.
  void Function(Map<String, dynamic> data)? onSeenAction;

  /// Route a tap immediately if a handler is wired, otherwise buffer it until
  /// one is assigned. Never drops the tap.
  void _dispatchTap(Map<String, dynamic> data) {
    final handler = _onTap;
    if (handler != null) {
      handler(data);
    } else {
      _pendingTap = data;
    }
  }

  bool _initialized = false;
  String? _registeredToken;
  String? _registeredLanguage;
  String? _registeredProfile;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<String>? _tokenRefreshSub;

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  late final ReleaseNotifier releases = ReleaseNotifier(_local);

  static const MethodChannel _platform = MethodChannel('soplay/platform');

  /// The words for channels and release notifications in the current
  /// language. Falls back to English while translations are still loading —
  /// this runs before the first frame, and a channel named after its
  /// translation key would be shown to the user in system settings.
  NotificationLabels labels() {
    const d = NotificationLabels();
    String t(String key, String fallback) {
      try {
        final v = 'release_notify.$key'.tr();
        return v.isEmpty || v == 'release_notify.$key' ? fallback : v;
      } catch (_) {
        return fallback;
      }
    }

    return NotificationLabels(
      channelGeneral: t('channel_general', d.channelGeneral),
      channelGeneralDesc: t('channel_general_desc', d.channelGeneralDesc),
      channelReleases: t('channel_releases', d.channelReleases),
      channelReleasesDesc: t('channel_releases_desc', d.channelReleasesDesc),
      channelAiring: t('channel_airing', d.channelAiring),
      channelAiringDesc: t('channel_airing_desc', d.channelAiringDesc),
      channelQuiet: t('channel_quiet', d.channelQuiet),
      channelQuietDesc: t('channel_quiet_desc', d.channelQuietDesc),
      episodeOne: t('episode_one', d.episodeOne),
      episodesMany: t('episodes_many', d.episodesMany),
      chapterOne: t('chapter_one', d.chapterOne),
      chaptersMany: t('chapters_many', d.chaptersMany),
      actionWatch: t('action_watch', d.actionWatch),
      actionRead: t('action_read', d.actionRead),
      actionSeen: t('action_seen', d.actionSeen),
      summaryTitle: t('summary_title', d.summaryTitle),
      summaryMore: t('summary_more', d.summaryMore),
      badgeEpisode: t('badge_episode', d.badgeEpisode),
      badgeChapter: t('badge_chapter', d.badgeChapter),
      epShort: t('ep_short', d.epShort),
      chShort: t('ch_short', d.chShort),
    );
  }

  Future<void>? _initializing;

  /// Shared by concurrent callers: two initialisations would each read the
  /// launch details and open a tapped notification twice.
  Future<void> ensureInitialized() {
    if (_initialized) return Future.value();
    return _initializing ??= _initialize().whenComplete(() => _initializing = null);
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    if (!Platform.isAndroid && !Platform.isIOS) {
      _initialized = true;
      return;
    }
    // Push is Android-only here, but the LOCAL plugin is what schedules airing
    // reminders — so iOS initialises it even though it never registers for FCM.
    if (Platform.isAndroid && Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    tz.initializeTimeZones();
    // Scheduling is done in the device's own zone: an airing time converted to
    // UTC and back through the wrong zone fires hours out.
    tz.setLocalLocation(tz.getLocation(await _deviceTimeZone()));

    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings(ReleaseNotifier.smallIcon),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: _onResponse,
      onDidReceiveBackgroundNotificationResponse: onBackgroundNotificationAction,
    );
    await releases.ensureChannels(labels());
    _initialized = true;

    // A tap on a local notification that started the app — the background
    // check's releases, airing reminders. FCM's own taps come through
    // getInitialMessage instead.
    try {
      final launch = await _local.getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if (launch?.didNotificationLaunchApp == true && response != null) {
        _onResponse(response);
      }
    } catch (_) {}
  }

  void _onResponse(NotificationResponse resp) {
    final payload = decodeNotificationPayload(resp.payload);
    if (payload == null) return;
    if (resp.actionId == ReleaseNotifier.actionSeen) {
      final seen = onSeenAction;
      if (seen != null) {
        seen(payload);
      } else {
        unawaited(_postSeen(payload));
      }
      unawaited(releases.refreshSummary(labels()));
      return;
    }
    _dispatchTap(payload);
  }

  Future<void> _postSeen(Map<String, dynamic> payload) async {
    final response = NotificationResponse(
      notificationResponseType: NotificationResponseType.selectedNotificationAction,
      actionId: ReleaseNotifier.actionSeen,
      payload: encodeNotificationPayload(payload),
    );
    await onBackgroundNotificationAction(response);
  }

  /// Renames the channels into the current language. Called once the
  /// translations have loaded, and after the language changes.
  Future<void> refreshChannels() async {
    if (!_initialized || !Platform.isAndroid) return;
    await releases.ensureChannels(labels());
  }

  /// The zone the phone is actually in.
  ///
  /// Falls back to UTC rather than throwing: a reminder in the wrong zone is
  /// bad, but a notification service that fails to start is worse.
  Future<String> _deviceTimeZone() async {
    try {
      return await FlutterTimezone.getLocalTimezone();
    } catch (_) {
      return 'UTC';
    }
  }

  // ─── permission ───────────────────────────────────────────────────────────

  /// Whether the OS lets this app post notifications right now.
  Future<bool> get permissionGranted async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    await ensureInitialized();
    try {
      if (Platform.isAndroid) {
        final android = _local
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        return await android?.areNotificationsEnabled() ?? false;
      }
      final ios = _local
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final options = await ios?.checkPermissions();
      return options?.isEnabled ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Asks the OS for permission to post notifications. Never called on its
  /// own — only behind the priming sheet or a switch the user flipped.
  Future<bool> requestPermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    await ensureInitialized();
    if (await permissionGranted) {
      await cooldown.accepted();
      return true;
    }
    var granted = false;
    try {
      if (Platform.isAndroid) {
        final android = _local
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        granted = await android?.requestNotificationsPermission() ?? false;
      } else {
        final ios = _local
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        granted =
            await ios?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      }
    } catch (_) {
      granted = false;
    }
    await cooldown.markSystemPromptShown();
    if (granted) await cooldown.accepted();
    return granted;
  }

  /// Denied in a way only system settings can undo: Android stops showing
  /// its prompt after the second refusal, and says so only by no longer
  /// wanting to explain itself.
  Future<bool> get permanentlyDenied async {
    if (!Platform.isAndroid) return false;
    if (await permissionGranted) return false;
    if (!cooldown.systemPromptShown) return false;
    try {
      final rationale = await _platform.invokeMethod<bool>('notificationRationale');
      return rationale != true;
    } catch (_) {
      return false;
    }
  }

  /// The app's notification page in system settings.
  Future<bool> openSystemSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _platform.invokeMethod<bool>('openNotificationSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  // ─── scheduling ───────────────────────────────────────────────────────────

  /// Schedules one reminder. Ids are the caller's, so it can replace its own.
  ///
  /// Inexact on purpose: exact alarms need a special permission on Android 12+
  /// that a user has to grant by hand, and "a few minutes either side of the
  /// episode" is what this is for anyway.
  Future<void> scheduleAt({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    Map<String, dynamic>? payload,
  }) async {
    await ensureInitialized();
    if (!Platform.isAndroid && !Platform.isIOS) return;
    // A reminder for a moment that has passed would fire immediately.
    if (!when.isAfter(DateTime.now())) return;
    final p = prefs;
    if (!p.allows('airing_reminder')) return;
    // Scheduled ahead, so quiet hours are judged for the moment it fires.
    final quiet = p.quiet.contains(when);
    final l = labels();

    await _local.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      NotificationDetails(
        android: AndroidNotificationDetails(
          quiet ? ReleaseNotifier.quietChannel : ReleaseNotifier.airingChannel,
          quiet ? l.channelQuiet : l.channelAiring,
          channelDescription: quiet ? l.channelQuietDesc : l.channelAiringDesc,
          icon: ReleaseNotifier.smallIcon,
          color: ReleaseNotifier.accent,
          importance: quiet ? Importance.low : Importance.defaultImportance,
          priority: quiet ? Priority.low : Priority.defaultPriority,
          silent: quiet,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: encodeNotificationPayload(payload),
    );
  }

  Future<void> cancelScheduled(int id) async {
    if (!_initialized) return;
    await _local.cancel(id);
  }

  /// Every id in [ids]. Used to clear a whole batch before scheduling the next.
  Future<void> cancelAllScheduled(Iterable<int> ids) async {
    if (!_initialized) return;
    for (final id in ids) {
      await _local.cancel(id);
    }
  }

  // ─── push ─────────────────────────────────────────────────────────────────

  /// Puts this DEVICE on the push list, account or no account.
  ///
  /// Called once at startup rather than from the login flow. Push used to begin
  /// at registration, so an announcement only ever reached the minority who had
  /// signed up — everyone else had the app installed and no way to be told
  /// anything.
  ///
  /// It no longer asks for permission. The prompt used to be raised on every
  /// launch before anyone knew what they would be told about; now it is asked
  /// for once there is a reason — a first follow, onboarding, a settings
  /// switch — behind the priming sheet. Registration still happens either way:
  /// someone who turns notifications on in system settings a week later should
  /// not have to be asked again here.
  Future<void> setup() async {
    // Every platform initialises: the local plugin is what schedules airing
    // reminders, and this is the only startup call that reaches it.
    await ensureInitialized();
    if (!Platform.isAndroid) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _registerToken(token);
    }

    _tokenRefreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen(
      _registerToken,
    );

    _foregroundSub ??= FirebaseMessaging.onMessage.listen(_showLocal);

    _openedSub ??= FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      _dispatchTap(_normalizeData(msg.data));
    });

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _dispatchTap(_normalizeData(initial.data));
    }
  }

  /// Signing out detaches the device from the account — it does not take the
  /// device off push.
  ///
  /// The token is deliberately NOT deleted. It used to be, which meant logging
  /// out also opted the phone out of every announcement until it next signed
  /// in; the server now unlinks the row and keeps it, so broadcasts continue
  /// and only that account's personal notifications stop.
  Future<void> unregister() async {
    if (!Platform.isAndroid) return;
    final token = _registeredToken ??
        await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    await repository.unregisterFcmToken(token);
    // Re-register as an anonymous device so the row's lastSeen keeps moving
    // and a later sign-in claims the same token.
    _registeredToken = null;
    _registeredLanguage = null;
    _registeredProfile = null;
    await _registerToken(token);
  }

  Future<void> dispose() async {
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
    await _tokenRefreshSub?.cancel();
    _foregroundSub = null;
    _openedSub = null;
    _tokenRefreshSub = null;
  }

  /// Re-sends the registration after the UI language or the active profile
  /// changed, and renames the channels.
  ///
  /// Safe to call when nothing is registered yet — the token is only known once
  /// Firebase has handed one over, and until then the next launch does the work.
  Future<void> refreshRegistration() async {
    unawaited(refreshChannels());
    final token = _registeredToken;
    if (token == null || token.isEmpty) return;
    await _registerToken(token);
  }

  /// Registers the device, and carries the UI language up with it.
  ///
  /// Push copy is the one text the client cannot translate — the OS draws the
  /// notification from what the server sent, and by then the app may not be
  /// running. So the server has to know the language, and this call is where it
  /// learns it: it happens on every launch, which means an account that never
  /// touches its profile still ends up on the right language.
  ///
  /// The guard keys on the language and the household profile as well as the
  /// token: the server records the profile from `X-Sozo-Profile` on this call,
  /// so a profile switch has to re-register or pushes keep going to the last
  /// one.
  Future<void> _registerToken(String token) async {
    final language = getIt<HiveService>().getLanguage();
    final profile = ProfileScope.remoteId;
    if (_registeredToken == token &&
        _registeredLanguage == language &&
        _registeredProfile == profile) {
      return;
    }
    final platform = Platform.isIOS ? 'ios' : 'android';
    final result = await repository.registerFcmToken(
      token: token,
      platform: platform,
      language: language,
    );
    if (result is Success) {
      _registeredToken = token;
      _registeredLanguage = language;
      _registeredProfile = profile;
    } else if (kDebugMode) {
      debugPrint('[FCM] register failed');
    }
  }

  // ─── showing ──────────────────────────────────────────────────────────────

  /// Show a local notification not tied to FCM (e.g. automatic downloads).
  ///
  /// Held back entirely when its type is switched off or quiet hours are on:
  /// what the app raises for itself can always wait for the app to be opened.
  Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    // iOS too.
    //
    // This was Android-only, which made it the odd one out: `scheduleAt` —
    // the airing reminders — has always handed the plugin a Darwin block and
    // worked on both. So everything that came through HERE was silently
    // dropped on iOS, and the thing that comes through here is the follow
    // check: an iPhone user following forty series was told about a new
    // episode exactly never.
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final p = prefs;
    if (!p.allows(data?['type']?.toString()) || p.quiet.contains(DateTime.now())) {
      return;
    }
    await ensureInitialized();
    final l = labels();
    await _local.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          ReleaseNotifier.generalChannel,
          l.channelGeneral,
          channelDescription: l.channelGeneralDesc,
          icon: ReleaseNotifier.smallIcon,
          color: ReleaseNotifier.accent,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: encodeNotificationPayload(data),
    );
  }

  /// A release this device found itself, drawn in the rich style.
  Future<void> showRelease(ReleaseAlert alert) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final p = prefs;
    if (!p.allows('new_release') || p.quiet.contains(DateTime.now())) return;
    await ensureInitialized();
    try {
      await releases.showRelease(alert, labels());
    } catch (e) {
      if (kDebugMode) debugPrint('[notify] release failed: $e');
    }
  }

  /// Takes a title's notification down once it has been opened or marked.
  Future<void> clearRelease(String provider, String contentUrl) async {
    if (!_initialized || !Platform.isAndroid) return;
    try {
      await releases.cancelFor(provider, contentUrl, labels());
    } catch (_) {}
  }

  /// "Send test notification" in settings. Ignores the per-type switches and
  /// quiet hours on purpose: it is asked for, now.
  Future<void> showTest({ReleaseAlert? sample}) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await ensureInitialized();
    final l = labels();
    if (sample != null) {
      await releases.showRelease(sample, l);
      return;
    }
    await _local.show(
      0x7E57,
      'Sozo',
      'release_notify.test_body'.tr(),
      NotificationDetails(
        android: AndroidNotificationDetails(
          ReleaseNotifier.generalChannel,
          l.channelGeneral,
          icon: ReleaseNotifier.smallIcon,
          color: ReleaseNotifier.accent,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> _showLocal(RemoteMessage msg) async {
    final data = _normalizeData(msg.data);
    final type = data['type']?.toString();
    if ((type == 'friend_request' || type == 'friend_accept') &&
        getIt.isRegistered<SocialService>()) {
      getIt<SocialService>().refreshOverview();
    }
    final p = prefs;
    final quiet = p.quiet.contains(DateTime.now());

    if (type == 'new_release') {
      final alert = ReleaseAlert.fromData(data);
      if (alert == null) return;
      final record = onReleasePush;
      if (record != null) {
        await record(alert, profileId: data['profileId']?.toString());
      }
      if (!p.allows(type)) return;
      await ensureInitialized();
      try {
        await releases.showRelease(alert, labels(), quiet: quiet);
      } catch (e) {
        if (kDebugMode) debugPrint('[notify] push release failed: $e');
      }
      return;
    }

    final n = msg.notification;
    final title = n?.title ?? data['title']?.toString();
    final body = n?.body ?? data['body']?.toString();
    if (title == null && body == null) return;
    if (!p.allows(type)) return;
    final l = labels();
    await _local.show(
      n?.hashCode ?? msg.messageId.hashCode,
      title ?? 'Sozo',
      body ?? '',
      NotificationDetails(
        android: AndroidNotificationDetails(
          quiet ? ReleaseNotifier.quietChannel : ReleaseNotifier.generalChannel,
          quiet ? l.channelQuiet : l.channelGeneral,
          channelDescription: quiet ? l.channelQuietDesc : l.channelGeneralDesc,
          icon: ReleaseNotifier.smallIcon,
          color: ReleaseNotifier.accent,
          importance: quiet ? Importance.low : Importance.high,
          priority: quiet ? Priority.low : Priority.high,
          silent: quiet,
        ),
      ),
      payload: encodeNotificationPayload(data),
    );
  }

  Map<String, dynamic> _normalizeData(Map<String, dynamic> data) {
    return data.map((k, v) => MapEntry(k.toString(), v));
  }
}
