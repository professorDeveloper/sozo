import 'dart:convert';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/notifications/domain/repositories/notifications_repository.dart';

typedef NotificationTapHandler = void Function(Map<String, dynamic> data);

class NotificationService {
  final NotificationsRepository repository;

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
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<String>? _tokenRefreshSub;

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static const _channel = AndroidNotificationChannel(
    'soplay_default',
    'SoPlay bildirishnomalari',
    description: 'Asosiy bildirishnomalar kanali',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  NotificationService({required this.repository});

  Future<void> ensureInitialized() async {
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
      InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: const DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (resp) {
        final payload = _decodePayload(resp.payload);
        if (payload != null) _dispatchTap(payload);
      },
    );
    final androidImpl = _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(_channel);
    await androidImpl?.createNotificationChannel(_airingChannel);
    _initialized = true;
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

  /// Reminders for episodes about to air.
  ///
  /// Its own channel so a person can silence airing reminders without losing
  /// the notifications that matter to their account.
  static const AndroidNotificationChannel _airingChannel =
      AndroidNotificationChannel(
    'sozo_airing',
    'Airing reminders',
    description: 'Fires shortly before an episode you follow goes out',
    importance: Importance.defaultImportance,
  );

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

    await _local.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      NotificationDetails(
        android: AndroidNotificationDetails(
          _airingChannel.id,
          _airingChannel.name,
          channelDescription: _airingChannel.description,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload == null ? null : jsonEncode(payload),
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

  /// Puts this DEVICE on the push list, account or no account.
  ///
  /// Called once at startup rather than from the login flow. Push used to begin
  /// at registration, so an announcement only ever reached the minority who had
  /// signed up — everyone else had the app installed and no way to be told
  /// anything.
  ///
  /// Registration also survives a denied permission prompt: the token is what
  /// the server addresses, and someone who turns notifications on in system
  /// settings a week later should not have to be asked again here.
  Future<void> setup() async {
    // Every platform initialises: the local plugin is what schedules airing
    // reminders, and this is the only startup call that reaches it.
    await ensureInitialized();
    if (!Platform.isAndroid) return;

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

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

  /// Re-sends the registration after the UI language changed.
  ///
  /// Safe to call when nothing is registered yet — the token is only known once
  /// Firebase has handed one over, and until then the next launch does the work.
  Future<void> refreshRegistration() async {
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
  /// The guard keys on the language as well as the token, so switching language
  /// re-registers instead of being swallowed as a duplicate.
  Future<void> _registerToken(String token) async {
    final language = getIt<HiveService>().getLanguage();
    if (_registeredToken == token && _registeredLanguage == language) return;
    final platform = Platform.isIOS ? 'ios' : 'android';
    final result = await repository.registerFcmToken(
      token: token,
      platform: platform,
      language: language,
    );
    if (result is Success) {
      _registeredToken = token;
      _registeredLanguage = language;
    } else if (kDebugMode) {
      debugPrint('[FCM] register failed');
    }
  }

  /// Show a local notification not tied to FCM (e.g. tracker "new episode").
  Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    if (!Platform.isAndroid) return;
    await ensureInitialized();
    await _local.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: (data == null || data.isEmpty) ? null : _encodePayload(data),
    );
  }

  Future<void> _showLocal(RemoteMessage msg) async {
    final n = msg.notification;
    if (n == null) return;
    final data = _normalizeData(msg.data);
    await _local.show(
      n.hashCode,
      n.title ?? 'SoPlay',
      n.body ?? '',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: _encodePayload(data),
    );
  }

  Map<String, dynamic> _normalizeData(Map<String, dynamic> data) {
    return data.map((k, v) => MapEntry(k.toString(), v));
  }

  String? _encodePayload(Map<String, dynamic> data) {
    if (data.isEmpty) return null;
    final entries = data.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent('${e.value}')}')
        .join('&');
    return entries;
  }

  Map<String, dynamic>? _decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    final out = <String, dynamic>{};
    for (final part in payload.split('&')) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      out[Uri.decodeComponent(part.substring(0, i))] =
          Uri.decodeComponent(part.substring(i + 1));
    }
    return out;
  }
}
