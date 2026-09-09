// ignore_for_file: invalid_use_of_protected_member
part of 'player_page.dart';

/// Handing the episode to a television.
///
/// The hand-off carries three things the receiver cannot obtain for itself: the
/// headers the CDN requires, the subtitle track the viewer is actually reading,
/// and the position they are at. Missing any one of them turns casting into a
/// worse way to watch — a 403, the wrong language, or starting over.
///
/// The phone stops playing but stays in the player. It is now the remote: the
/// same transport controls, wired to the session instead of the local surface.
/// Leaving the page would strand a viewer whose only pause button had just gone
/// with it.
extension _PlayerCast on _PlayerPageState {
  /// One place decides what can be cast, and it is [castTypeFor].
  ///
  /// A downloaded episode is deliberately among the things it refuses: the
  /// package can serve a local file to a receiver, but it is the case least
  /// likely to be worth the battery and the wait, and a slow offer is worse
  /// than none.
  bool get _canCast {
    final url = _videoUrl;
    if (url == null || url.isEmpty) return false;
    return castTypeFor(url, hint: _mediaType) != null;
  }

  CastMedia? _buildCastMedia() {
    final url = _videoUrl;
    if (url == null) return null;
    final type = castTypeFor(url, hint: _mediaType);
    if (type == null) return null;

    // Only the track being read. A receiver handed the whole list shows a
    // picker on the television, which is a remote control the viewer does not
    // have in their hand.
    final active = _subtitles.where((s) => s.isDefault).toList();
    final subtitles = [
      for (final s in active)
        if (CastHandoff.isSendable(s.file))
          CastSubtitle(
            url: s.file,
            label: s.label,
            language: s.label,
            format: CastHandoff.subtitleFormatFor(s.file),
          ),
    ];

    return CastMedia(
      url: url,
      type: type,
      httpHeaders: _headers,
      title: widget.args.title,
      imageUrl: widget.args.thumbnail,
      // Where they are, not where the episode starts. Casting mid-episode is
      // the common case — the phone was the wrong screen all along.
      startPosition: CastHandoff.startPositionFor(
        isLive: _isLive,
        position: _controller?.value.position,
      ),
      subtitles: subtitles,
      defaultSubtitle: subtitles.isEmpty ? null : subtitles.first,
    );
  }

  Future<void> _openCastSheet() async {
    final media = _buildCastMedia();
    if (media == null) {
      _toast('player.cast_unsupported'.tr());
      return;
    }

    final cast = _cast;
    cast.startDiscovery();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => AnimatedBuilder(
        animation: cast,
        builder: (context, _) => _CastSheet(
          cast: cast,
          onPick: (device) async {
            Navigator.of(sheetContext).pop();
            await _castTo(device, media);
          },
        ),
      ),
    );
    cast.stopDiscovery();
  }

  Future<void> _castTo(CastDevice device, CastMedia media) async {
    // Paused before the hand-off, not after. Two copies of the same episode
    // playing a second apart in the same room is the thing people notice, and
    // they notice it as the app being broken.
    await _controller?.pause();
    final ok = await _cast.castTo(device, media);
    if (!mounted) return;
    if (!ok) {
      await _controller?.play();
      _toast('player.cast_failed'.tr(args: [device.name]));
      return;
    }
    setState(() {});
  }

  Future<void> _stopCasting() async {
    await _cast.stopCasting();
    if (!mounted) return;
    // Back to where the television got to, so stopping the cast is not a way
    // to lose ten minutes.
    setState(() {});
    await _controller?.play();
  }

  /// Renders nothing unless a session is live, so the stack can hold it
  /// unconditionally.
  Widget _buildCastOverlay() {
    return AnimatedBuilder(
      animation: _cast,
      builder: (context, _) => _cast.isCasting
          ? Positioned.fill(
              child: _CastOverlay(
                cast: _cast,
                title: widget.args.title,
                onStop: _stopCasting,
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

class _CastSheet extends StatelessWidget {
  const _CastSheet({required this.cast, required this.onPick});

  final CastController cast;
  final ValueChanged<CastDevice> onPick;

  @override
  Widget build(BuildContext context) {
    final devices = cast.devices;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'player.cast_to'.tr(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (cast.scanning)
                  const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (devices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  cast.scanning
                      ? 'player.cast_searching'.tr()
                      : 'player.cast_none'.tr(),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              )
            else
              for (final d in devices)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.tv_rounded, color: Colors.white70),
                  title: Text(
                    d.name,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  subtitle: Text(
                    d.address.address,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  onTap: () => onPick(d),
                ),
          ],
        ),
      ),
    );
  }
}

/// What the phone shows while the television is the screen.
///
/// A full cover rather than a badge. The local surface is paused on a frame
/// that no longer matches what is on the TV, and leaving it visible under a
/// small indicator reads as two players disagreeing — the exact confusion the
/// hand-off is supposed to remove.
class _CastOverlay extends StatelessWidget {
  const _CastOverlay({
    required this.cast,
    required this.title,
    required this.onStop,
  });

  final CastController cast;
  final String title;
  final Future<void> Function() onStop;

  @override
  Widget build(BuildContext context) {
    final playing = cast.state == SessionState.playing;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cast_connected_rounded,
                  size: 44, color: Colors.white70),
              const SizedBox(height: 14),
              Text(
                'player.cast_active'.tr(args: [cast.device?.name ?? 'TV']),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CastButton(
                    icon: Icons.replay_10_rounded,
                    onTap: () => _nudge(cast, const Duration(seconds: -10)),
                  ),
                  const SizedBox(width: 18),
                  _CastButton(
                    icon: playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    big: true,
                    onTap: () => playing ? cast.pause() : cast.play(),
                  ),
                  const SizedBox(width: 18),
                  _CastButton(
                    icon: Icons.forward_30_rounded,
                    onTap: () => _nudge(cast, const Duration(seconds: 30)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: onStop,
                icon: const Icon(Icons.stop_rounded, size: 18),
                label: Text('player.cast_stop'.tr()),
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Relative seeking, from the position the receiver reports.
  ///
  /// The phone's own controller was paused at the hand-off and has been wrong
  /// ever since, so seeking from it would jump the television back to wherever
  /// the phone stopped.
  static Future<void> _nudge(CastController cast, Duration by) async {
    final at = await cast.positionStream?.first;
    if (at == null) return;
    final target = at + by;
    await cast.seek(target < Duration.zero ? Duration.zero : target);
  }
}

class _CastButton extends StatelessWidget {
  const _CastButton({
    required this.icon,
    required this.onTap,
    this.big = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool big;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: big ? 40 : 28),
        color: Colors.white,
      );
}
