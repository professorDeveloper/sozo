import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens this app's page in the system settings, where permissions live.
/// Returns false where there is no such page or it could not be opened.
Future<bool> openAppSettings() async {
  if (kIsWeb) return false;
  try {
    if (Platform.isAndroid) {
      return await const MethodChannel(
            'soplay/platform',
          ).invokeMethod<bool>('openAppSettings') ??
          false;
    }
    if (Platform.isIOS) {
      return await launchUrl(Uri.parse('app-settings:'));
    }
  } catch (_) {}
  return false;
}
