import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:soplay/features/notifications/data/notification_actions.dart';
import 'package:soplay/features/notifications/data/notification_payload.dart';
import 'package:soplay/features/notifications/data/notification_prefs.dart';
import 'package:soplay/features/notifications/data/release_notifier.dart';
import 'package:soplay/features/tracker/data/release_inbox.dart';

/// A push that arrived with the app in the background or closed.
///
/// A push carrying a `notification` block has already been drawn by Android
/// by the time this runs; all that is left is to remember the release for the
/// feed. A data-only push is drawn here, through the same [ReleaseNotifier]
/// the app uses, and only if the person's switches allow its type.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessage(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
  } catch (_) {}
  final data = message.data.map((k, v) => MapEntry(k, v as Object?));
  final type = data['type']?.toString();
  final inbox = await ReleaseInbox.open();
  final snapshot = inbox.readSnapshot();
  final prefs = snapshot?.prefs ?? const NotificationPrefs();
  final labels = snapshot?.labels ?? const NotificationLabels();
  final quiet = prefs.quiet.contains(DateTime.now());

  if (type == 'new_release') {
    final alert = ReleaseAlert.fromData(data);
    if (alert == null) return;
    await inbox.post(
      ReleaseEvent.fromAlert(alert, profileId: data['profileId']?.toString()),
    );
    if (message.notification != null || !prefs.allows(type)) return;
    final plugin = await _plugin(labels);
    await ReleaseNotifier(plugin).showRelease(alert, labels, quiet: quiet);
    return;
  }

  if (message.notification != null || !prefs.allows(type)) return;
  final title = data['title']?.toString() ?? '';
  final body = data['body']?.toString() ?? '';
  if (title.isEmpty && body.isEmpty) return;
  final plugin = await _plugin(labels);
  await plugin.show(
    message.messageId.hashCode & 0x0fffffff,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        quiet ? ReleaseNotifier.quietChannel : ReleaseNotifier.generalChannel,
        quiet ? labels.channelQuiet : labels.channelGeneral,
        icon: ReleaseNotifier.smallIcon,
        color: ReleaseNotifier.accent,
        importance: quiet ? Importance.low : Importance.high,
        priority: quiet ? Priority.low : Priority.high,
        silent: quiet,
      ),
    ),
    payload: encodeNotificationPayload(data.cast<String, dynamic>()),
  );
}

Future<FlutterLocalNotificationsPlugin> _plugin(NotificationLabels labels) async {
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings(ReleaseNotifier.smallIcon),
    ),
    onDidReceiveBackgroundNotificationResponse: onBackgroundNotificationAction,
  );
  await ReleaseNotifier(plugin).ensureChannels(labels);
  return plugin;
}
