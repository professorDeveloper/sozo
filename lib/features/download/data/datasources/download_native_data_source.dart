import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the Android foreground service reports about one transfer.
@immutable
class NativeDownloadState {
  const NativeDownloadState({
    required this.id,
    required this.status,
    required this.artefactPath,
    required this.completedUnits,
    required this.totalUnits,
    required this.sizeBytes,
    required this.error,
  });

  final String id;

  /// `downloading` | `paused` | `completed` | `failed` | `cancelled`.
  final String status;

  /// Absolute, because the service only ever deals in absolute paths. The
  /// repository converts it back to a relative one before it is stored — a
  /// path from the platform is a fact about this launch, not about the
  /// download.
  final String artefactPath;

  final int completedUnits;
  final int totalUnits;
  final int sizeBytes;
  final String error;

  factory NativeDownloadState.fromJson(Map<dynamic, dynamic> json) =>
      NativeDownloadState(
        id: json['id']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        artefactPath: json['localPath']?.toString() ?? '',
        completedUnits: (json['completedUnits'] as num?)?.toInt() ??
            (json['downloadedBytes'] as num?)?.toInt() ??
            0,
        totalUnits: (json['totalUnits'] as num?)?.toInt() ??
            (json['totalBytes'] as num?)?.toInt() ??
            0,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        error: json['error']?.toString() ?? '',
      );
}

/// The Android foreground-service downloader.
///
/// Android is the one platform where the transfer must outlive the UI: a
/// download that stops the moment somebody leaves the app is not a download.
/// Everywhere else the Dart engine runs in-process, which is why every method
/// here is safe to call and inert off Android.
class DownloadNativeDataSource {
  const DownloadNativeDataSource();

  static const MethodChannel _channel = MethodChannel('soplay/downloads');

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Asks for the notification permission, and does not care much about the
  /// answer.
  ///
  /// It used to gate the whole feature: a viewer who declined the Android 13
  /// prompt could not download anything at all, with no message explaining
  /// why. The permission buys a visible progress notification, not the
  /// transfer — a foreground service runs either way — so the answer is
  /// recorded and ignored.
  Future<bool> requestNotificationPermission() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'requestNotificationPermission',
          ) ??
          false;
    } on PlatformException catch (e) {
      debugPrint('[downloads] notification permission: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Starts a transfer. Returns false when the platform refused — on Android
  /// 12+ a foreground service cannot always be started from the background,
  /// and pretending otherwise is how a queue silently does nothing.
  Future<bool> start({
    required String id,
    required String title,
    required String url,
    required String artefactPath,
    required Map<String, String> headers,
    required String kind,
    required List<String> pageUrls,
    required bool wifiOnly,
  }) async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('startDownload', {
            'id': id,
            'title': title,
            'url': url,
            'localPath': artefactPath,
            'headers': headers,
            'kind': kind,
            'pageUrls': pageUrls,
            'wifiOnly': wifiOnly,
          }) ??
          false;
    } on PlatformException catch (e) {
      debugPrint('[downloads] start refused: ${e.code} ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<List<NativeDownloadState>> states() async {
    if (!isSupported) return const [];
    try {
      final raw =
          await _channel.invokeMethod<String>('getDownloadStates') ?? '{}';
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const [];
      return decoded.values
          .whereType<Map>()
          .map(NativeDownloadState.fromJson)
          .toList();
    } catch (e) {
      debugPrint('[downloads] could not read native states: $e');
      return const [];
    }
  }

  Future<void> pause(String id) => _invoke('pauseDownload', {'id': id});

  Future<void> cancel(String id) => _invoke('cancelDownload', {'id': id});

  Future<void> cancelAll() => _invoke('cancelAllDownloads');

  Future<void> forget(String id) =>
      _invoke('removeDownloadState', {'id': id});

  /// Free bytes on the volume the app's files live on, or null when the
  /// platform did not answer.
  ///
  /// [path] narrows it to one volume — the SD card's free space is not the
  /// phone's, and offering a location without saying how much room it has is
  /// asking somebody to guess.
  Future<int?> freeBytes({String? path}) async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<int>(
        'freeSpaceBytes',
        path == null ? null : <String, dynamic>{'path': path},
      );
    } catch (_) {
      return null;
    }
  }

  /// Every volume the app may write to without asking for a permission.
  ///
  /// Returns the raw maps; the repository turns them into entities. Empty off
  /// Android, where there is one location and no choice to offer.
  Future<List<Map<String, dynamic>>> volumes() async {
    if (!isSupported) return const [];
    try {
      final raw = await _channel.invokeMethod<String>('downloadVolumes') ?? '[]';
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final entry in decoded)
          if (entry is Map) Map<String, dynamic>.from(entry),
      ];
    } catch (e) {
      debugPrint('[downloads] could not list volumes: $e');
      return const [];
    }
  }

  /// Copies a finished file into the shared Downloads folder and returns the
  /// user-visible location.
  Future<String?> exportToDownloads({
    required String path,
    required String name,
  }) async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('exportToDownloads', {
        'path': path,
        'name': name,
      });
    } on PlatformException catch (e) {
      debugPrint('[downloads] export failed: ${e.message}');
      return null;
    }
  }

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } on PlatformException catch (e) {
      debugPrint('[downloads] $method failed: ${e.message}');
    } on MissingPluginException {
      // An older host without this method. Nothing to do and nothing to say.
    }
  }
}
