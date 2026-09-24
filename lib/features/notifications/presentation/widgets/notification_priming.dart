import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/app_buttons.dart';
import 'package:soplay/core/widgets/item_appear.dart';
import 'package:soplay/core/widgets/sozo_mark.dart';
import 'package:soplay/features/notifications/data/services/notification_service.dart';
import 'package:soplay/features/notifications/presentation/widgets/animated_bell.dart';
import 'package:soplay/features/tracker/data/follow_service.dart';

/// Explains what Sozo will notify about, then asks the OS.
///
/// Returns whether notifications are allowed when it is done. Shows nothing
/// and returns straight away when they already are, and when the person said
/// "Not now" recently (see PrimingCooldown). When Android has stopped asking —
/// two refusals — the sheet offers system settings instead and notices when
/// the person comes back with the switch on.
///
/// [titleHint] names the show that prompted it ("the moment Frieren gets a new
/// episode"); the mock notification uses it too.
Future<bool> showNotificationPriming(
  BuildContext context, {
  String? titleHint,
}) async {
  if (!Platform.isAndroid && !Platform.isIOS) return false;
  final service = getIt<NotificationService>();
  if (await service.permissionGranted) return true;
  if (!service.cooldown.canAsk) return false;
  final blocked = await service.permanentlyDenied;
  if (!context.mounted) return false;
  final result = await showAdaptiveModal<bool>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    builder: (_) => _PrimingSheet(
      titleHint: titleHint?.trim().isEmpty ?? true ? null : titleHint!.trim(),
      blocked: blocked,
      service: service,
    ),
  );
  if (result == true) return true;
  if (result == null) await service.cooldown.declined();
  return service.permissionGranted;
}

enum _Phase { ask, blocked, done }

class _PrimingSheet extends StatefulWidget {
  const _PrimingSheet({
    required this.titleHint,
    required this.blocked,
    required this.service,
  });

  final String? titleHint;
  final bool blocked;
  final NotificationService service;

  @override
  State<_PrimingSheet> createState() => _PrimingSheetState();
}

class _PrimingSheetState extends State<_PrimingSheet>
    with WidgetsBindingObserver {
  late _Phase _phase = widget.blocked ? _Phase.blocked : _Phase.ask;
  bool _busy = false;
  int _ring = 0;
  Timer? _ringer;
  bool _sentToSettings = false;

  /// A poster for the mock: the show that prompted this, else the latest
  /// follow, else none (the mock draws a placeholder).
  late final String? _poster = () {
    try {
      final follows = getIt<FollowService>().list();
      final hint = widget.titleHint;
      final match = hint == null
          ? null
          : follows.where((t) => t.title == hint).firstOrNull;
      final pick = match ?? follows.firstOrNull;
      final url = pick?.thumbnail ?? '';
      return url.startsWith('http') ? url : null;
    } catch (_) {
      return null;
    }
  }();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || MediaQuery.disableAnimationsOf(context)) return;
      Future<void>.delayed(const Duration(milliseconds: 380), () {
        if (mounted) setState(() => _ring++);
      });
      _ringer = Timer.periodic(const Duration(milliseconds: 3200), (_) {
        if (mounted && _phase != _Phase.done) setState(() => _ring++);
      });
    });
  }

  @override
  void dispose() {
    _ringer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from system settings: if the switch is on now, this is done.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_sentToSettings) return;
    _sentToSettings = false;
    unawaited(() async {
      if (await widget.service.permissionGranted) await _finish();
    }());
  }

  Future<void> _turnOn() async {
    if (_busy) return;
    HapticFeedback.selectionClick();
    if (_phase == _Phase.blocked) {
      _sentToSettings = await widget.service.openSystemSettings();
      return;
    }
    setState(() => _busy = true);
    final granted = await widget.service.requestPermission();
    if (!mounted) return;
    if (granted) {
      await _finish();
      return;
    }
    final blocked = await widget.service.permanentlyDenied;
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (blocked) _phase = _Phase.blocked;
    });
    if (!blocked) {
      await widget.service.cooldown.declined();
      if (mounted) Navigator.of(context).pop(false);
    }
  }

  Future<void> _finish() async {
    await widget.service.cooldown.accepted();
    if (!mounted) return;
    HapticFeedback.lightImpact();
    setState(() {
      _busy = false;
      _phase = _Phase.done;
      _ring++;
    });
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _notNow() async {
    await widget.service.cooldown.declined();
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final hint = widget.titleHint;
    final blocked = _phase == _Phase.blocked;
    final done = _phase == _Phase.done;
    final title = done
        ? 'release_notify.priming_enabled'.tr()
        : blocked
        ? 'release_notify.priming_blocked_title'.tr()
        : 'release_notify.priming_title'.tr();
    final body = blocked
        ? 'release_notify.priming_blocked_body'.tr()
        : hint != null
        ? 'release_notify.priming_body_title'.tr(args: [hint])
        : 'release_notify.priming_body'.tr();

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textHint.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              ItemAppear(
                index: 0,
                child: _Illustration(
                  ring: _ring,
                  done: done,
                  showTitle: hint ?? 'release_notify.priming_sample_show'.tr(),
                  poster: _poster,
                ),
              ),
              const SizedBox(height: 22),
              ItemAppear(
                index: 1,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Text(
                    title,
                    key: ValueKey(title),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ItemAppear(
                index: 2,
                child: Text(
                  body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14.5,
                    height: 1.45,
                  ),
                ),
              ),
              if (!blocked && !done) ...[
                const SizedBox(height: 18),
                ItemAppear(
                  index: 3,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Point(
                        icon: Icons.photo_rounded,
                        text: 'release_notify.priming_point_releases'.tr(),
                      ),
                      _Point(
                        icon: Icons.bedtime_rounded,
                        text: 'release_notify.priming_point_quiet'.tr(),
                      ),
                      _Point(
                        icon: Icons.notifications_off_outlined,
                        text: 'release_notify.priming_point_control'.tr(),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (!done) ...[
                ItemAppear(
                  index: 4,
                  child: AppPrimaryButton(
                    label: blocked
                        ? 'release_notify.priming_open_settings'.tr()
                        : 'release_notify.priming_turn_on'.tr(),
                    icon: blocked
                        ? Icons.settings_rounded
                        : Icons.notifications_active_rounded,
                    loading: _busy,
                    onPressed: _turnOn,
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: _busy ? null : _notNow,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    minimumSize: const Size(double.infinity, 44),
                  ),
                  child: Text('release_notify.priming_not_now'.tr()),
                ),
              ] else
                const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 7, 12, 7),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A bell over a mock of the notification itself, with a second one tucked
/// behind it — what somebody following a few shows actually gets.
class _Illustration extends StatelessWidget {
  const _Illustration({
    required this.ring,
    required this.done,
    required this.showTitle,
    required this.poster,
  });

  final int ring;
  final bool done;
  final String showTitle;
  final String? poster;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 214,
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.35),
                  radius: 0.9,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.22),
                    AppColors.primary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            child: Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? AppColors.success : AppColors.primary,
                boxShadow: [
                  BoxShadow(
                    color: (done ? AppColors.success : AppColors.primary)
                        .withValues(alpha: 0.45),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: done
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 32)
                  : AnimatedBell(
                      state: BellState.on,
                      color: AppColors.onPrimary,
                      ringColor: Colors.white,
                      size: 30,
                      ringToken: ring,
                    ),
            ),
          ),
          PositionedDirectional(
            top: 104,
            start: 26,
            end: 26,
            child: Transform.scale(
              scale: 0.94,
              child: Opacity(
                opacity: 0.45,
                child: _MockCard(
                  title: '···',
                  body: 'release_notify.chapter_one'.tr(args: ['88']),
                  poster: null,
                  compact: true,
                ),
              ),
            ),
          ),
          PositionedDirectional(
            top: 84,
            start: 6,
            end: 6,
            child: _MockCard(
              title: showTitle,
              body: 'release_notify.episode_one'.tr(args: ['12']),
              poster: poster,
            ),
          ),
        ],
      ),
    );
  }
}

class _MockCard extends StatelessWidget {
  const _MockCard({
    required this.title,
    required this.body,
    required this.poster,
    this.compact = false,
  });

  final String title;
  final String body;
  final String? poster;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const SozoMark(size: 13, color: Colors.white),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Sozo',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '  ·  ${'time.now'.tr()}',
                      style: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Flexible(
                        child: _MockAction(label: 'release_notify.action_watch'.tr()),
                      ),
                      const SizedBox(width: 14),
                      Flexible(
                        child: _MockAction(label: 'release_notify.action_seen'.tr()),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: compact ? 40 : 52,
              height: compact ? 54 : 72,
              child: poster == null
                  ? _PosterPlaceholder(compact: compact)
                  : CachedNetworkImage(
                      imageUrl: poster!,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => _PosterPlaceholder(compact: compact),
                      placeholder: (_, _) => _PosterPlaceholder(compact: compact),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MockAction extends StatelessWidget {
  const _MockAction({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label.toUpperCase(),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: AppColors.primary,
      fontSize: 11.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.4,
    ),
  );
}

class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.primary.withValues(alpha: 0.85), AppColors.primaryDark],
      ),
    ),
    child: Center(
      child: Icon(
        Icons.movie_filter_rounded,
        color: Colors.white.withValues(alpha: 0.9),
        size: compact ? 18 : 24,
      ),
    ),
  );
}
