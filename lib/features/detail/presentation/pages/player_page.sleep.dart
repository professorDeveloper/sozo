// ignore_for_file: invalid_use_of_protected_member
part of 'player_page.dart';

/// Sleep timer.
///
/// Two shapes, because "I am falling asleep" arrives in two shapes. A clock
/// countdown suits a film; [_sleepAtEpisodeEnd] suits a series, where the thing
/// the viewer actually wants is *this* episode and not the next four the
/// auto-advance would have queued up behind it.
///
/// Firing pauses rather than closing the player. Closing would throw away the
/// resume position the viewer is most likely to want in the morning, and it is
/// hostile to the case this feature exists to serve — the viewer who is still
/// awake and reaches for the screen. Pausing is recoverable in one tap; a closed
/// player is not.
///
/// It also releases the wakelock, which is the half that makes it a *sleep*
/// timer rather than a pause button on a delay: the player normally holds the
/// screen on for the whole session, so without this the phone would sit lit and
/// paused all night.
///
/// Session-scoped on purpose — nothing here is persisted. A timer that survived
/// into tomorrow's viewing would stop playback for reasons the viewer set last
/// night and has no memory of.
extension _PlayerSleepTimer on _PlayerPageState {
  /// Options offered in the sheet. `null` duration means "end of episode".
  static const List<Duration> _presets = [
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(minutes: 45),
    Duration(hours: 1),
    Duration(hours: 2),
  ];

  bool get _sleepArmed => _sleepDeadline != null || _sleepAtEpisodeEnd;

  /// What the settings tile shows: remaining minutes, the episode-end mode, or
  /// "off". Rounded up so a timer with 30 seconds left reads `1m` rather than
  /// `0m`, which would look like it had already expired.
  String get _sleepValueLabel {
    if (_sleepAtEpisodeEnd) return 'player.sleep_episode_end'.tr();
    final deadline = _sleepDeadline;
    if (deadline == null) return 'general.off'.tr();
    final left = deadline.difference(DateTime.now());
    if (left.isNegative) return 'general.off'.tr();
    final minutes = (left.inSeconds / 60).ceil();
    return 'player.sleep_minutes_short'.tr(args: ['$minutes']);
  }

  void _armSleepDuration(Duration d) {
    _cancelSleepTimer();
    final deadline = DateTime.now().add(d);
    setState(() {
      _sleepDeadline = deadline;
      _sleepAtEpisodeEnd = false;
    });
    // A ticker rather than a single Timer(d): the label counts down, and the
    // sheet may be reopened at any point to check on it.
    _sleepTicker = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      if (DateTime.now().isBefore(deadline)) {
        setState(() {});
        return;
      }
      _fireSleepTimer();
    });
  }

  void _armSleepAtEpisodeEnd() {
    _cancelSleepTimer();
    setState(() {
      _sleepAtEpisodeEnd = true;
      _sleepDeadline = null;
    });
  }

  void _cancelSleepTimer() {
    _sleepTicker?.cancel();
    _sleepTicker = null;
    if (!mounted) {
      _sleepDeadline = null;
      _sleepAtEpisodeEnd = false;
      return;
    }
    setState(() {
      _sleepDeadline = null;
      _sleepAtEpisodeEnd = false;
    });
  }

  /// Pause, release the screen, say so.
  ///
  /// The message matters more than it looks: a player that stopped on its own
  /// with no explanation reads as a bug, and this one stops minutes or hours
  /// after the viewer set it up.
  Future<void> _fireSleepTimer() async {
    _sleepTicker?.cancel();
    _sleepTicker = null;
    if (mounted) {
      setState(() {
        _sleepDeadline = null;
        _sleepAtEpisodeEnd = false;
      });
    }
    try {
      await _controller?.pause();
    } catch (_) {
      // A controller that is already gone has nothing to pause, and the
      // wakelock below is still worth releasing.
    }
    try {
      await WakelockPlus.disable();
    } catch (_) {}
    if (!mounted) return;
    // Controls up and kept up, so the viewer who is still awake sees why it
    // stopped and can hit play without hunting for the tap target. The hide
    // timer is cancelled rather than restarted: playback is paused, and a
    // paused player that hides its own controls is the thing this is avoiding.
    _hideTimer?.cancel();
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
      _controlsAnimation.forward();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('player.sleep_fired'.tr()),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _openSleepSheet() {
    showAdaptiveModal<void>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.bedtime_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'player.sleep_timer'.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              _SleepOptionTile(
                label: 'general.off'.tr(),
                selected: !_sleepArmed,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _cancelSleepTimer();
                },
              ),
              for (final d in _PlayerSleepTimer._presets)
                _SleepOptionTile(
                  label: d.inMinutes < 60
                      ? 'player.sleep_minutes'.tr(args: ['${d.inMinutes}'])
                      : 'player.sleep_hours'.tr(args: ['${d.inHours}']),
                  selected: false,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _armSleepDuration(d);
                  },
                ),
              // Only meaningful for a series: on a film "end of episode" and
              // "end of file" are the same thing, and the player already stops
              // there on its own.
              if (widget.args.isSerial)
                _SleepOptionTile(
                  label: 'player.sleep_episode_end'.tr(),
                  selected: _sleepAtEpisodeEnd,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _armSleepAtEpisodeEnd();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _SleepOptionTile extends StatelessWidget {
  const _SleepOptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      onTap: onTap,
      title: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : Colors.white70,
          fontSize: 14,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      trailing: selected
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
          : null,
    );
  }
}
