import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr/qr.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/app_buttons.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_event.dart';
import 'package:soplay/features/onboarding/data/tv_pairing_service.dart';
import 'package:soplay/features/onboarding/presentation/widgets/onboarding_focus_button.dart';
import 'package:soplay/features/onboarding/presentation/widgets/onboarding_scaffold.dart';

/// Signing a television in without typing: a QR code and a short code for the
/// phone's "Link a TV" screen, polled until the phone says yes.
class TvPairingPanel extends StatefulWidget {
  const TvPairingPanel({super.key, required this.onGuest});

  final VoidCallback onGuest;

  @override
  State<TvPairingPanel> createState() => _TvPairingPanelState();
}

class _TvPairingPanelState extends State<TvPairingPanel> {
  final TvPairingService _service = getIt<TvPairingService>();
  TvPairing? _pairing;
  QrImage? _qr;
  bool _expired = false;
  bool _failed = false;
  bool _polling = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _create();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    _timer?.cancel();
    setState(() {
      _pairing = null;
      _expired = false;
      _failed = false;
    });
    try {
      final pairing = await _service.create();
      if (!mounted) return;
      setState(() {
        _pairing = pairing;
        _qr = QrImage(
          QrCode.fromData(
            data: pairing.link,
            errorCorrectLevel: QrErrorCorrectLevel.M,
          ),
        );
      });
      _timer = Timer.periodic(pairing.interval, (_) => _poll());
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _poll() async {
    final pairing = _pairing;
    if (pairing == null || _polling) return;
    _polling = true;
    try {
      final status = await _service.poll(pairing);
      if (!mounted) return;
      switch (status) {
        case TvPairingStatus.approved:
          _timer?.cancel();
          context.read<AuthBloc>().add(const AuthStarted());
        case TvPairingStatus.expired:
          _timer?.cancel();
          setState(() => _expired = true);
        case TvPairingStatus.pending:
          break;
      }
    } catch (_) {
      // A missed poll is retried on the next tick.
    } finally {
      _polling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pairing = _pairing;
    final qr = _qr;
    final Widget code;
    if (_failed || _expired) {
      code = _CodeMessage(
        text: _failed
            ? 'onboarding.tv_pair_failed'.tr()
            : 'onboarding.tv_pair_expired'.tr(),
        action: 'onboarding.tv_pair_new_code'.tr(),
        onAction: _create,
      );
    } else if (pairing == null || qr == null) {
      code = const SizedBox(
        width: 220,
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    } else {
      code = Container(
        width: 232,
        height: 232,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.35),
              blurRadius: 40,
            ),
          ],
        ),
        child: Semantics(
          label: 'onboarding.tv_pair_qr_label'.tr(),
          image: true,
          child: CustomPaint(painter: _QrPainter(qr)),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        code,
        const SizedBox(width: 40),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OnboardingHeading(
                title: 'onboarding.tv_pair_title'.tr(),
                subtitle: 'onboarding.tv_pair_body'.tr(),
              ),
              const SizedBox(height: 20),
              if (pairing != null && !_expired)
                Semantics(
                  label: pairing.userCode.split('').join(' '),
                  child: ExcludeSemantics(
                    child: Text(
                      pairing.userCode,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 8,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              if (pairing != null && !_expired) const _Waiting(),
              const SizedBox(height: 24),
              OnboardingFocusButton(
                autofocus: true,
                child: AppSecondaryButton(
                  label: 'onboarding.account_guest'.tr(),
                  expand: false,
                  onPressed: widget.onGuest,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Waiting extends StatefulWidget {
  const _Waiting();

  @override
  State<_Waiting> createState() => _WaitingState();
}

class _WaitingState extends State<_Waiting>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!MediaQuery.disableAnimationsOf(context) && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        FadeTransition(
          opacity: Tween(begin: 0.3, end: 1.0).animate(_pulse),
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'onboarding.tv_pair_waiting'.tr(),
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: OnbType.body,
          ),
        ),
      ],
    );
  }
}

class _CodeMessage extends StatelessWidget {
  const _CodeMessage({
    required this.text,
    required this.action,
    required this.onAction,
  });

  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 232,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.qr_code_2_rounded,
            size: 72,
            color: AppColors.textHint,
          ),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: OnbType.body,
            ),
          ),
          const SizedBox(height: 12),
          OnboardingFocusButton(
            child: AppPrimaryButton(
              label: action,
              expand: false,
              onPressed: onAction,
            ),
          ),
        ],
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.qr);

  final QrImage qr;

  @override
  void paint(Canvas canvas, Size size) {
    final n = qr.moduleCount;
    final cell = size.shortestSide / n;
    final paint = Paint()..color = const Color(0xFF0B0B0B);
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (!qr.isDark(r, c)) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(c * cell, r * cell, cell + 0.4, cell + 0.4),
            Radius.circular(cell * 0.2),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.qr != qr;
}
