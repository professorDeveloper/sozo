import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/remote/data/remote_control_service.dart';
import 'package:soplay/features/remote/presentation/remote_controller.dart';

/// The phone as a remote for the TV.
///
/// Two halves earn the screen: a keyboard, because entering text with a d-pad
/// is the worst thing about any TV app, and transport controls, because the
/// physical remote is always on the other sofa.
class TvRemotePage extends StatefulWidget {
  const TvRemotePage({super.key});

  @override
  State<TvRemotePage> createState() => _TvRemotePageState();
}

class _TvRemotePageState extends State<TvRemotePage>
    with WidgetsBindingObserver {
  late final RemoteController _controller = RemoteController(
    service: getIt<RemoteControlService>(),
  );
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onChange);
    _controller.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onChange);
    _controller.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Nobody is looking at the remote from the app switcher, and polling a TV
    // from the background is how a remote left open drains a battery.
    _controller.setPaused(state != AppLifecycleState.resumed);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<void> Function(String id) action) async {
    HapticFeedback.selectionClick();
    final problem = await _controller.send(action);
    if (problem == null || !mounted) return;
    _say(switch (problem) {
      'offline' => 'remote.tv_offline'.tr(),
      'no-device' => 'remote.no_devices'.tr(),
      _ => 'remote.command_failed'.tr(),
    });
  }

  void _say(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'remote.title'.tr(),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: _controller.load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    switch (_controller.status) {
      case RemoteStatus.loading:
        return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));

      case RemoteStatus.failed:
        return _Message(
          icon: Icons.cloud_off_rounded,
          text: 'remote.load_failed'.tr(),
          actionLabel: 'remote.retry'.tr(),
          onAction: _controller.load,
        );

      case RemoteStatus.noDevices:
        return _Message(
          icon: Icons.tv_off_rounded,
          text: 'remote.no_devices'.tr(),
          actionLabel: 'remote.retry'.tr(),
          onAction: _controller.load,
        );

      case RemoteStatus.ready:
        return _ready();
    }
  }

  Widget _ready() {
    final canControl = _controller.canControl;

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh: _controller.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          _ConnectionBanner(
            device: _controller.selected,
            online: _controller.online,
            state: _controller.tvState,
          ),
          const SizedBox(height: 12),

          // Shown even for a single TV: "which one am I driving" is the first
          // question a remote has to answer, and hiding the answer when there
          // is exactly one is how it stops being obvious.
          _DeviceList(
            devices: _controller.devices,
            selected: _controller.selected,
            onSelect: _controller.select,
          ),

          const SizedBox(height: 18),
          _Disabled(
            disabled: !canControl,
            child: _KeyboardCard(
              controller: _search,
              onSubmit: (text) {
                final query = text.trim();
                if (query.isEmpty) return;
                _run((id) => getIt<RemoteControlService>().type(id, query));
              },
            ),
          ),

          const SizedBox(height: 14),
          _Disabled(
            disabled: !canControl,
            child: _DpadCard(
              onDirection: (d) =>
                  _run((id) => getIt<RemoteControlService>().dpad(id, d)),
              onBack: () => _run(getIt<RemoteControlService>().back),
              onHome: () => _run(getIt<RemoteControlService>().home),
            ),
          ),

          const SizedBox(height: 14),
          _Disabled(
            disabled: !canControl,
            child: _TransportCard(
              playing: _controller.tvState?.playing ?? false,
              onPlayPause: () => _run(getIt<RemoteControlService>().playPause),
              onSeekBack: () =>
                  _run((id) => getIt<RemoteControlService>().seekBy(id, -10000)),
              onSeekForward: () =>
                  _run((id) => getIt<RemoteControlService>().seekBy(id, 10000)),
              onPrevious: () => _run(getIt<RemoteControlService>().previous),
              onNext: () => _run(getIt<RemoteControlService>().next),
            ),
          ),
        ],
      ),
    );
  }
}

/// Says, in one line, which TV this is and whether it is listening.
class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({
    required this.device,
    required this.online,
    required this.state,
  });

  final RemoteDevice? device;
  final bool online;
  final RemoteTvState? state;

  String _clock(int ms) {
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final name = device?.name ?? '';
    final playing = state;
    final accent = online ? AppColors.success : AppColors.textHint;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              online ? Icons.cast_connected_rounded : Icons.tv_off_rounded,
              color: accent,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  online
                      ? 'remote.connected_to'.tr(namedArgs: {'device': name})
                      : 'remote.not_connected_to'.tr(namedArgs: {'device': name}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  !online
                      ? 'remote.turn_tv_on'.tr()
                      : playing?.title ?? 'remote.idle'.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textHint,
                  ),
                ),
                if (online && (playing?.hasPlayback ?? false)) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      value: (playing!.positionMs ?? 0) / playing.durationMs!,
                      backgroundColor: AppColors.surfaceVariant,
                      valueColor: AlwaysStoppedAnimation(AppColors.primary),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_clock(playing.positionMs ?? 0)} / ${_clock(playing.durationMs!)}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList({
    required this.devices,
    required this.selected,
    required this.onSelect,
  });

  final List<RemoteDevice> devices;
  final RemoteDevice? selected;
  final ValueChanged<RemoteDevice> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: devices.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final device = devices[i];
          final active = device.id == selected?.id;
          return GestureDetector(
            onTap: () => onSelect(device),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active
                    ? AppColors.primary.withValues(alpha: 0.16)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(19),
                border: Border.all(
                  color: active ? AppColors.primary : Colors.transparent,
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: device.online
                          ? AppColors.success
                          : AppColors.textHint,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    device.name,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: active
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Dims and blocks a control group rather than letting every tap fail.
class _Disabled extends StatelessWidget {
  const _Disabled({required this.disabled, required this.child});

  final bool disabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: disabled ? 0.4 : 1,
      child: IgnorePointer(ignoring: disabled, child: child),
    );
  }
}

class _KeyboardCard extends StatelessWidget {
  const _KeyboardCard({required this.controller, required this.onSubmit});

  final TextEditingController controller;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    return _Card(
      label: 'remote.search_on_tv'.tr(),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: onSubmit,
              decoration: InputDecoration(
                hintText: 'remote.search_hint'.tr(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: () => onSubmit(controller.text),
            icon: const Icon(Icons.send_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _DpadCard extends StatelessWidget {
  const _DpadCard({
    required this.onDirection,
    required this.onBack,
    required this.onHome,
  });

  final ValueChanged<String> onDirection;
  final VoidCallback onBack;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return _Card(
      label: 'remote.navigation'.tr(),
      child: Column(
        children: [
          _Key(
            icon: Icons.keyboard_arrow_up_rounded,
            onTap: () => onDirection('up'),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Key(
                icon: Icons.keyboard_arrow_left_rounded,
                onTap: () => onDirection('left'),
              ),
              const SizedBox(width: 10),
              _Key(
                icon: Icons.circle_outlined,
                primary: true,
                onTap: () => onDirection('center'),
              ),
              const SizedBox(width: 10),
              _Key(
                icon: Icons.keyboard_arrow_right_rounded,
                onTap: () => onDirection('right'),
              ),
            ],
          ),
          _Key(
            icon: Icons.keyboard_arrow_down_rounded,
            onTap: () => onDirection('down'),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 17),
                label: Text('remote.back'.tr()),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: onHome,
                icon: const Icon(Icons.home_rounded, size: 17),
                label: Text('remote.home'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TransportCard extends StatelessWidget {
  const _TransportCard({
    required this.playing,
    required this.onPlayPause,
    required this.onSeekBack,
    required this.onSeekForward,
    required this.onPrevious,
    required this.onNext,
  });

  final bool playing;
  final VoidCallback onPlayPause;
  final VoidCallback onSeekBack;
  final VoidCallback onSeekForward;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _Card(
      label: 'remote.playback'.tr(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _Key(icon: Icons.skip_previous_rounded, onTap: onPrevious),
          _Key(icon: Icons.replay_10_rounded, onTap: onSeekBack),
          _Key(
            icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            primary: true,
            onTap: onPlayPause,
          ),
          _Key(icon: Icons.forward_10_rounded, onTap: onSeekForward),
          _Key(icon: Icons.skip_next_rounded, onTap: onNext),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
              color: AppColors.textHint,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.icon, required this.onTap, this.primary = false});

  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: primary ? AppColors.primary : AppColors.surfaceVariant,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: primary ? 58 : 48,
            height: primary ? 58 : 48,
            child: Icon(icon, color: Colors.white, size: primary ? 27 : 23),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 46,
              color: AppColors.textHint.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
