import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/torrent/torrent_engine.dart';
import 'package:soplay/core/torrent/torrent_status.dart';
import 'package:soplay/features/torrent/data/torrent_trackers.dart';
import 'package:soplay/features/torrent/domain/entities/torrent_result.dart';
import 'package:soplay/features/torrent/presentation/widgets/torrent_consent_dialog.dart';
import 'package:soplay/features/torrent/presentation/widgets/torrent_file_picker_sheet.dart';

/// A torrent that is ready to play.
class TorrentStreamHandle {
  const TorrentStreamHandle({
    required this.url,
    required this.hash,
    required this.file,
    required this.title,
  });

  /// A plain, seekable `http://127.0.0.1:…` URL. The player has no idea it is
  /// a torrent, which is the entire design.
  final Uri url;

  final String hash;
  final TorrentFileEntry file;

  /// What to show as the title — the chosen file, not the torrent, since a
  /// season pack's torrent name says nothing about which episode is playing.
  final String title;
}

/// Turns a torrent link into something the player can open.
///
/// The sequence, and why each step is here:
///
///   1. **Platform check.** The engine is Android-only; elsewhere the feature
///      should be absent rather than fail.
///   2. **Consent.** See [TorrentConsent] — a torrent uploads from the user's
///      device, which nothing else in the app does.
///   3. **Start the server**, attaching the public tracker list. Without those
///      trackers a magnet from an indexer often has no announce URL at all and
///      falls back to DHT alone.
///   4. **Add the link and wait for metadata.** A magnet has no file list until
///      the swarm answers.
///   5. **Pick a file** when the torrent holds more than one video.
///   6. **Fill the read-ahead buffer** before handing the URL over.
///
/// Step 6 is the one that is easy to skip and expensive to skip. Give the
/// player the URL immediately and it works — but `initialize()` then blocks
/// until the buffer fills anyway, behind a black screen, with no progress, no
/// peer count and no way out. Measured on a real swarm that was nineteen
/// seconds of nothing. Doing the wait here costs the same time and spends it
/// showing what is happening.
abstract final class TorrentPlayback {
  static Future<TorrentStreamHandle?> prepare(
    BuildContext context,
    TorrentResult result, {
    required TorrentEngine engine,
  }) async {
    if (result.health == SwarmHealth.dead) {
      _toast(ScaffoldMessenger.maybeOf(context), 'torrent.dead_warning'.tr());
      return null;
    }

    final link = result.engineLink(
      extraTrackers: TorrentTrackers.forIndexer(result.indexerId),
    );
    if (link == null) return null;

    return prepareLink(
      context,
      link,
      engine: engine,
      title: result.title,
      trackers: TorrentTrackers.forIndexer(result.indexerId),
    );
  }

  /// The same flow starting from a bare magnet or `.torrent` URL.
  ///
  /// Split out from [prepare] because a torrent does not only arrive from
  /// Sozo's own search: CloudStream plugins return magnets as extractor links,
  /// and those deserve the identical treatment rather than a second, worse
  /// implementation.
  static Future<TorrentStreamHandle?> prepareLink(
    BuildContext context,
    String link, {
    required TorrentEngine engine,
    String? title,
    List<String> trackers = TorrentTrackers.defaults,
  }) async {
    if (!engine.isSupported) {
      _toast(ScaffoldMessenger.maybeOf(context), 'torrent.unsupported'.tr());
      return null;
    }

    if (!await TorrentConsent.ensure(context)) return null;
    if (!context.mounted) return null;

    // Captured before the awaits. Everything after this point runs across async
    // gaps, and re-reading them from `context` there is the classic way to
    // touch a disposed element when the user leaves mid-preparation.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);

    final progress = _PreparationProgress(torrentName: title);
    _openSheet(navigator, progress);

    String? addedHash;
    try {
      progress.message = 'torrent.preparing'.tr();

      await engine.ensureStarted(trackers: trackers);
      if (progress.cancelled) return null;

      final added = await engine.add(link, title: title);
      addedHash = added.hash;
      if (progress.cancelled) return null;

      progress.message = 'torrent.fetching_metadata'.tr();

      final status = await engine.awaitMetadata(
        added.hash,
        onProgress: progress.adopt,
      );
      if (progress.cancelled) return null;

      final videos = status.videoFiles;
      if (videos.isEmpty) {
        _closeSheet(navigator);
        _toast(messenger, 'torrent.no_video_in_torrent'.tr());
        await engine.drop(status.hash);
        return null;
      }

      var file = videos.first;
      if (videos.length > 1) {
        // The picker needs the screen to itself; the sheet comes back for the
        // buffering step right after.
        _closeSheet(navigator);
        if (!context.mounted) return null;

        final picked = await TorrentFilePickerSheet.show(context, videos);
        if (picked == null) {
          // Backing out of the picker is a cancel, so stop the swarm rather
          // than leaving it downloading in the background.
          await engine.drop(status.hash);
          return null;
        }
        file = picked;
        _openSheet(navigator, progress);
      }

      progress
        ..message = 'torrent.buffering_title'.tr()
        ..fileName = file.name;

      engine.startPreload(status.hash, file);
      await engine.awaitPreload(status.hash, onProgress: progress.adopt);
      if (progress.cancelled) {
        await engine.drop(status.hash);
        return null;
      }

      _closeSheet(navigator);

      return TorrentStreamHandle(
        url: engine.streamUri(status.hash, file),
        hash: status.hash,
        file: file,
        title: file.name,
      );
    } on TimeoutException {
      _closeSheet(navigator);
      _toast(messenger, 'torrent.metadata_timeout'.tr());
      if (addedHash != null) await engine.drop(addedHash);
      return null;
    } catch (_) {
      _closeSheet(navigator);
      _toast(messenger, 'torrent.engine_failed'.tr());
      if (addedHash != null) await engine.drop(addedHash);
      return null;
    } finally {
      progress.dispose();
    }
  }

  static void _openSheet(NavigatorState navigator, _PreparationProgress progress) {
    if (!navigator.mounted) return;
    unawaited(showModalBottomSheet<void>(
      context: navigator.context,
      backgroundColor: AppColors.surface,
      isDismissible: false,
      enableDrag: false,
      // Full width and bottom-anchored. Without this the sheet inherits the
      // theme's dialog-ish sizing and renders as a small floating card, which
      // is neither a sheet nor a dialog and reads as a rendering bug.
      constraints: const BoxConstraints.expand(height: double.infinity)
          .copyWith(minHeight: 0, maxHeight: double.infinity),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PreparationSheet(progress: progress),
    ));
  }

  static void _closeSheet(NavigatorState navigator) {
    if (navigator.mounted && navigator.canPop()) navigator.pop();
  }

  static void _toast(ScaffoldMessengerState? messenger, String message) {
    if (messenger == null || !messenger.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

/// Shared state between the preparation steps and the sheet showing them.
class _PreparationProgress extends ChangeNotifier {
  _PreparationProgress({this.torrentName});

  final String? torrentName;

  String _message = '';
  String? _fileName;
  TorrentStatus? _status;
  bool cancelled = false;

  String get message => _message;
  set message(String value) {
    _message = value;
    notifyListeners();
  }

  String? get fileName => _fileName;
  set fileName(String? value) {
    _fileName = value;
    notifyListeners();
  }

  TorrentStatus? get status => _status;

  /// Takes the latest server snapshot. Called from the polling loops, which run
  /// while the sheet may already have been disposed.
  void adopt(TorrentStatus value) {
    _status = value;
    notifyListeners();
  }

  int get peers => _status?.activePeers ?? _status?.totalPeers ?? 0;
  double get downloadSpeed => _status?.downloadSpeed ?? 0;
  double? get bufferProgress => _status?.preloadProgress;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _PreparationSheet extends StatelessWidget {
  const _PreparationSheet({required this.progress});

  final _PreparationProgress progress;

  static String _speed(double bytesPerSecond) {
    if (bytesPerSecond < 1024) return '0 KB/s';
    if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(0)} KB/s';
    }
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        width: double.infinity,
        child: ListenableBuilder(
          listenable: progress,
          builder: (context, _) {
            final buffer = progress.bufferProgress;
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          Icons.hub_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          progress.message,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (buffer != null)
                        Text(
                          '${(buffer * 100).round()}%',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                  if (progress.fileName != null ||
                      progress.torrentName != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      progress.fileName ?? progress.torrentName!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textHint,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      // Indeterminate until the server reports a buffer target:
                      // a bar sitting at 0 % looks broken, a moving one does not
                      // claim progress it cannot measure.
                      value: buffer,
                      minHeight: 4,
                      backgroundColor: AppColors.surfaceVariant,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // The honest signal that something is happening. Metadata
                  // arrives the moment one peer answers, so a rising peer count
                  // means progress and a stuck zero means the swarm is empty —
                  // which a spinner alone can never say.
                  Row(
                    children: [
                      Icon(
                        Icons.arrow_downward_rounded,
                        size: 13,
                        color: AppColors.textHint,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        _speed(progress.downloadSpeed),
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Icon(
                        Icons.hub_outlined,
                        size: 12,
                        color: AppColors.textHint,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'torrent.stats_peers'.tr(args: ['${progress.peers}']),
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          progress.cancelled = true;
                          Navigator.of(context).pop();
                        },
                        child: Text(
                          'general.cancel'.tr(),
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
