import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:soplay/features/notifications/data/notification_payload.dart';
import 'package:soplay/features/notifications/data/release_notifier.dart';
import 'package:soplay/features/tracker/data/release_inbox.dart';

/// "Mark seen" pressed while the app is not running.
///
/// The plugin runs this in an isolate of its own, so the seen mark goes to the
/// inbox for the app to apply rather than into Hive. The notification itself
/// was already dismissed by the button.
@pragma('vm:entry-point')
Future<void> onBackgroundNotificationAction(NotificationResponse response) async {
  if (response.actionId != ReleaseNotifier.actionSeen) return;
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final data = decodeNotificationPayload(response.payload);
  if (data == null) return;
  try {
    final inbox = await ReleaseInbox.open();
    await inbox.post(seenEventFrom(data));
    final labels = inbox.readSnapshot()?.labels ?? const NotificationLabels();
    await ReleaseNotifier(FlutterLocalNotificationsPlugin()).refreshSummary(labels);
  } catch (_) {}
}

ReleaseEvent seenEventFrom(Map<String, dynamic> data) => ReleaseEvent(
  kind: ReleaseEventKind.seen,
  provider: '${data['provider'] ?? ''}',
  contentUrl: '${data['contentUrl'] ?? ''}',
  at: DateTime.now().millisecondsSinceEpoch,
);
