import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/torrent/torrent_engine.dart';
import 'package:soplay/core/torrent/torrent_status.dart';
import 'package:soplay/core/torrent/torrent_stream_url.dart';

/// Live swarm readout while a torrent is playing.
///
/// ## Why the player needs this and an HTTP stream does not
///
/// When a normal stream stalls, the spinner is the whole story: the CDN is
/// slow, wait or give up. When a *torrent* stalls the reason is knowable and
/// actionable — the swarm is thin, the pre-buffer is at 30%, four peers are
/// connected and the number is climbing. A bare spinner throws that away and
/// leaves the user unable to tell "ten more seconds" from "this will never
/// start", which is the single most common complaint about torrent streaming.
///
/// So this shows speed, peer count, and — while the head of the file is still
/// filling — how far along the pre-buffer is. It renders nothing at all for
/// non-torrent playback, so the player can hand it every URL unconditionally.
class TorrentStatsOverlay extends StatefulWidget {
  const TorrentStatsOverlay({
    super.key,
    required this.videoUrl,
    this.visible = true,
  });

  /// The URL currently playing. Anything that is not a local torrent stream
  /// makes this widget collapse to nothing — see [TorrentStreamUrl.parse].
  final String? videoUrl;

  /// Whether the player's controls are showing. The readout follows them,
  /// except while the pre-buffer is filling: that is exactly when the user is
  /// staring at a stalled picture wondering what is happening, and hiding the
  /// explanation then would defeat the point.
  final bool visible;

  @override
  State<TorrentStatsOverlay> createState() => _TorrentStatsOverlayState();
}

class _TorrentStatsOverlayState extends State<TorrentStatsOverlay> {
  final TorrentEngine _engine = TorrentEngine();

  StreamSubscription<TorrentStatus>? _subscription;
  TorrentStatus? _status;
  String? _watchedHash;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(TorrentStatsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) _sync();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _engine.dispose();
    super.dispose();
  }

  /// Starts, switches or stops the poll to match the URL now playing.
  void _sync() {
    final parsed = TorrentStreamUrl.parse(widget.videoUrl);

    if (parsed == null) {
      _subscription?.cancel();
      _subscription = null;
      _watchedHash = null;
      if (_status != null) setState(() => _status = null);
      return;
    }

    // Same torrent, different file (the user picked another episode from the
    // same pack): the swarm poll is unchanged, so leave it alone rather than
    // restarting it and blanking the readout for a second.
    if (parsed.hash == _watchedHash) return;

    _subscription?.cancel();
    _watchedHash = parsed.hash;

    // The server is process-wide; this instance just adopts the port the URL
    // was built with, so there is nothing to start and nothing to wait for.
    _engine.attach(parsed.port);
    _subscription = _engine.watch(parsed.hash).listen((status) {
      if (mounted) setState(() => _status = status);
    });
  }

  static String _speed(double bytesPerSecond) {
    if (bytesPerSecond < 1024) return '0 KB/s';
    if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(0)} KB/s';
    }
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (status == null) return const SizedBox.shrink();

    final preload = status.preloadProgress;
    final filling = preload != null && preload < 1;

    // Hidden controls normally hide this too — but not while the pre-buffer is
    // filling, when it is the only thing explaining the frozen picture.
    final show = widget.visible || filling;

    return Positioned(
      // Clear of the back/title row above and the seek bar below, so it never
      // collides with the controls in either state.
      top: MediaQuery.of(context).padding.top + 62,
      left: 16,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: show ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.arrow_downward_rounded,
                      size: 13,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _speed(status.downloadSpeed),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(
                      Icons.hub_outlined,
                      size: 12,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'torrent.stats_peers'.tr(
                        args: ['${status.activePeers ?? status.totalPeers ?? 0}'],
                      ),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11.5,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                if (filling) ...[
                  const SizedBox(height: 6),
                  Text(
                    'torrent.buffering'
                        .tr(args: ['${(preload * 100).round()}']),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 128,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: preload,
                        minHeight: 3,
                        backgroundColor: Colors.white24,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
