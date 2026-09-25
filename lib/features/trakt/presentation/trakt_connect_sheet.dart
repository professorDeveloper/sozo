import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/trakt/data/trakt_service.dart';
import 'package:soplay/features/trakt/presentation/trakt_brand.dart';

/// Connecting Trakt with the device flow, on one sheet.
///
/// The code is the whole interaction, so it is the biggest thing on the
/// sheet, grouped 4+4 the way people read codes aloud, and copied by a tap.
/// The sheet polls on its own at the interval Trakt asked for, counts the
/// code down, and says in words what happened: waiting, connected, expired,
/// denied, or that the network dropped and it is still trying.
class TraktConnectSheet extends StatefulWidget {
  const TraktConnectSheet({super.key});

  /// Resolves true when the account was linked.
  static Future<bool> show(BuildContext context) async {
    final linked = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const TraktConnectSheet(),
    );
    return linked ?? false;
  }

  @override
  State<TraktConnectSheet> createState() => _TraktConnectSheetState();
}

enum _Stage { starting, waiting, linked, expired, denied, unavailable }

class _TraktConnectSheetState extends State<TraktConnectSheet> {
  final TraktService _trakt = getIt<TraktService>();
  TraktDeviceCode? _code;
  _Stage _stage = _Stage.starting;
  bool _offline = false;
  bool _copied = false;
  Timer? _poll;
  Timer? _tick;
  Duration _interval = const Duration(seconds: 5);

  /// How long the code was valid for when issued, for the countdown bar.
  Duration _life = const Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    _poll?.cancel();
    _tick?.cancel();
    setState(() {
      _stage = _Stage.starting;
      _code = null;
      _offline = false;
    });
    final code = await _trakt.startLink();
    if (!mounted) return;
    if (code == null) {
      setState(() => _stage = _Stage.unavailable);
      return;
    }
    setState(() {
      _code = code;
      _stage = _Stage.waiting;
      _interval = code.interval;
      _life = code.expiresAt.difference(DateTime.now());
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (DateTime.now().isAfter(code.expiresAt) && _stage == _Stage.waiting) {
        _poll?.cancel();
        setState(() => _stage = _Stage.expired);
      } else {
        setState(() {});
      }
    });
    _schedule();
  }

  void _schedule() {
    _poll?.cancel();
    _poll = Timer(_interval, _pollOnce);
  }

  Future<void> _pollOnce() async {
    if (!mounted || _stage != _Stage.waiting) return;
    final r = await _trakt.poll();
    if (!mounted || _stage != _Stage.waiting) return;
    switch (r) {
      case TraktPoll.linked:
        _tick?.cancel();
        HapticFeedback.mediumImpact();
        setState(() => _stage = _Stage.linked);
        Timer(const Duration(milliseconds: 1200), () {
          if (mounted) Navigator.of(context).pop(true);
        });
      case TraktPoll.expired:
        setState(() => _stage = _Stage.expired);
      case TraktPoll.denied:
        setState(() => _stage = _Stage.denied);
      case TraktPoll.slowDown:
        _interval += const Duration(seconds: 5);
        _schedule();
      case TraktPoll.failed:
        setState(() => _offline = true);
        _schedule();
      case TraktPoll.pending:
        if (_offline) setState(() => _offline = false);
        _schedule();
    }
  }

  Future<void> _copy() async {
    final code = _code?.userCode;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    HapticFeedback.selectionClick();
    setState(() => _copied = true);
    Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _open() async {
    final url = _code?.verificationUrl ?? 'https://trakt.tv/activate';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  static String _grouped(String code) =>
      code.length == 8 ? '${code.substring(0, 4)} ${code.substring(4)}' : code;

  @override
  Widget build(BuildContext context) {
    final code = _code;
    final left = code == null
        ? Duration.zero
        : code.expiresAt.difference(DateTime.now());
    final fraction = code == null || _life.inSeconds <= 0
        ? 0.0
        : (left.inSeconds / _life.inSeconds).clamp(0.0, 1.0);
    final mm = left.inMinutes.clamp(0, 99);
    final ss = (left.inSeconds % 60).clamp(0, 59).toString().padLeft(2, '0');

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const TraktLogo(size: 30),
                const SizedBox(width: 10),
                Text(
                  'trakt.connect_title'.tr(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: KeyedSubtree(
                key: ValueKey(_stage),
                child: _body(code, fraction, '$mm:$ss'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(TraktDeviceCode? code, double fraction, String left) {
    switch (_stage) {
      case _Stage.starting:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator()),
        );
      case _Stage.unavailable:
        return _Outcome(
          icon: Icons.cloud_off_rounded,
          color: AppColors.textSecondary,
          text: 'trakt.unavailable'.tr(),
          action: 'general.retry'.tr(),
          onAction: _start,
        );
      case _Stage.expired:
        return _Outcome(
          icon: Icons.timer_off_outlined,
          color: AppColors.textSecondary,
          text: 'trakt.code_expired'.tr(),
          action: 'trakt.new_code'.tr(),
          onAction: _start,
        );
      case _Stage.denied:
        return _Outcome(
          icon: Icons.block_rounded,
          color: kTraktRed,
          text: 'trakt.denied'.tr(),
          action: 'trakt.new_code'.tr(),
          onAction: _start,
        );
      case _Stage.linked:
        return _Outcome(
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF3FB950),
          text: 'trakt.connected_as'.tr(args: [_trakt.viewer?.name ?? '']),
        );
      case _Stage.waiting:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Step(n: 1, text: 'trakt.step_open'.tr()),
            const SizedBox(height: 8),
            _Step(n: 2, text: 'trakt.step_enter'.tr()),
            const SizedBox(height: 16),
            Semantics(
              button: true,
              label: 'trakt.copy_code'.tr(),
              child: Material(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _copy,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Column(
                      children: [
                        Text(
                          _grouped(code!.userCode),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 4,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _copied
                                  ? Icons.check_rounded
                                  : Icons.copy_rounded,
                              size: 15,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _copied
                                  ? 'trakt.copied'.tr()
                                  : 'trakt.copy_code'.tr(),
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: kTraktRed,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _open,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text('trakt.open_activate'.tr()),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 3,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                color: kTraktRed,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _offline ? 'trakt.reconnecting'.tr() : 'trakt.waiting'.tr(),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                Text(
                  'trakt.expires_in'.tr(args: [left]),
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        );
    }
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});
  final int n;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: kTraktRed.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
        child: Text(
          '$n',
          style: const TextStyle(
            color: kTraktRed,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            height: 1.35,
          ),
        ),
      ),
    ],
  );
}

class _Outcome extends StatelessWidget {
  const _Outcome({
    required this.icon,
    required this.color,
    required this.text,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final Color color;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Column(
      children: [
        Icon(icon, size: 44, color: color),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
            height: 1.4,
          ),
        ),
        if (action != null) ...[
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: kTraktRed,
              foregroundColor: Colors.white,
            ),
            onPressed: onAction,
            child: Text(action!),
          ),
        ],
      ],
    ),
  );
}
