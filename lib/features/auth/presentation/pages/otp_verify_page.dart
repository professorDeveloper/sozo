import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_event.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_state.dart';
import 'package:soplay/features/auth/presentation/widgets/auth_widgets.dart';

class OtpVerifyPage extends StatefulWidget {
  const OtpVerifyPage({super.key, required this.email});
  final String email;

  @override
  State<OtpVerifyPage> createState() => _OtpVerifyPageState();
}

class _OtpVerifyPageState extends State<OtpVerifyPage>
    with WidgetsBindingObserver {
  static const int _length = 6;
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _ticker;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focus.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      _syncCooldownFromState();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        if (_controller.text.length >= _length) return;
        _focus.unfocus();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (!mounted) return;
        _focus.requestFocus();
        SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      });
    }
  }

  void _syncCooldownFromState() {
    final state = context.read<AuthBloc>().state;
    if (state is AuthOtpPending) {
      _startCountdown(state.cooldownUntil);
    }
  }

  void _startCountdown(DateTime until) {
    _ticker?.cancel();
    void tick() {
      if (!mounted) return;
      final left = until.difference(DateTime.now());
      setState(() {
        _remaining = left.isNegative ? Duration.zero : left;
      });
      if (left.isNegative) _ticker?.cancel();
    }

    tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  void _onCodeChanged(String value) {
    setState(() {});
    if (value.length == _length) {
      _submit();
    }
  }

  void _submit() {
    final code = _controller.text.trim();
    if (code.length != _length) return;
    FocusScope.of(context).unfocus();
    context.read<AuthBloc>().add(
      AuthOtpVerifyRequested(email: widget.email, code: code),
    );
  }

  void _resend() {
    _controller.clear();
    _focus.requestFocus();
    context.read<AuthBloc>().add(AuthOtpResendRequested(widget.email));
  }

  bool _isKeyboardOpen() {
    return MediaQuery.viewInsetsOf(context).bottom > 0 || _focus.hasFocus;
  }

  bool _dismissKeyboardIfOpen() {
    if (_isKeyboardOpen()) {
      FocusScope.of(context).unfocus();
      return true;
    }
    return false;
  }

  void _back() {
    if (_dismissKeyboardIfOpen()) return;
    context.read<AuthBloc>().add(const AuthOtpReset());
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/register');
    }
  }

  String _formatCooldown(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (m > 0) return '$m:${s.toString().padLeft(2, '0')}';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _back();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: BlocListener<AuthBloc, AuthState>(
          listenWhen: (a, b) =>
              a.runtimeType != b.runtimeType ||
              (a is AuthOtpPending &&
                  b is AuthOtpPending &&
                  a.cooldownUntil != b.cooldownUntil),
          listener: (context, state) {
            if (state is AuthLoaded) {
              context.go('/main');
              return;
            }
            if (state is AuthOtpPending) {
              _startCountdown(state.cooldownUntil);
              if (state.justResent) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('auth.code_resent'.tr()),
                    backgroundColor: AppColors.surface,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              }
            }
          },
          child: SafeArea(
            child: BlocBuilder<AuthBloc, AuthState>(
              builder: (context, state) {
                final pending = state is AuthOtpPending ? state : null;
                final verifying = pending?.verifying ?? false;
                final resending = pending?.resending ?? false;
                final error = pending?.error;
                final canResend = _remaining == Duration.zero && !resending;
                final codeLength = _controller.text.length;
                final canSubmit = codeLength == _length && !verifying;

                return LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight - 32,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _TopBar(onBack: _back),
                            const SizedBox(height: 32),
                            Center(
                              child: Container(
                                width: 84,
                                height: 84,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.12,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.mark_email_read_rounded,
                                  color: AppColors.primary,
                                  size: 40,
                                ),
                              ),
                            ),
                            const SizedBox(height: 22),
                            const Text(
                              'Verification code',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text.rich(
                              TextSpan(
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                                children: [
                                  const TextSpan(
                                    text: 'We sent a 6-digit code to\n',
                                  ),
                                  TextSpan(
                                    text: widget.email,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 32),
                            _OtpField(
                              controller: _controller,
                              focusNode: _focus,
                              length: _length,
                              onChanged: _onCodeChanged,
                              hasError: error != null,
                            ),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                              child: error == null
                                  ? const SizedBox(height: 0)
                                  : Padding(
                                      padding: const EdgeInsets.only(top: 14),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.error_outline_rounded,
                                            color: AppColors.error,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              error,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: AppColors.error,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 28),
                            AuthPrimaryButton(
                              label: 'auth.verify'.tr(),
                              loading: verifying,
                              onPressed: canSubmit ? _submit : null,
                            ),
                            const SizedBox(height: 22),
                            _ResendRow(
                              canResend: canResend,
                              resending: resending,
                              remaining: _remaining,
                              onResend: _resend,
                              formatCooldown: _formatCooldown,
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 42,
          height: 42,
          child: Material(
            color: AppColors.surface,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onBack,
              child: const Icon(
                Icons.arrow_back_rounded,
                color: AppColors.textPrimary,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ResendRow extends StatelessWidget {
  const _ResendRow({
    required this.canResend,
    required this.resending,
    required this.remaining,
    required this.onResend,
    required this.formatCooldown,
  });

  final bool canResend;
  final bool resending;
  final Duration remaining;
  final VoidCallback onResend;
  final String Function(Duration) formatCooldown;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          "Didn't receive code?",
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(width: 4),
        TextButton(
          onPressed: canResend ? onResend : null,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: AppColors.primary,
            disabledForegroundColor: AppColors.textHint,
          ),
          child: Text(
            resending
                ? 'Sending...'
                : canResend
                ? 'Resend'
                : 'Resend in ${formatCooldown(remaining)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _OtpField extends StatelessWidget {
  const _OtpField({
    required this.controller,
    required this.focusNode,
    required this.length,
    required this.onChanged,
    required this.hasError,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int length;
  final ValueChanged<String> onChanged;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: 1,
            height: 1,
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(length),
                ],
                onChanged: onChanged,
                autofillHints: const [AutofillHints.oneTimeCode],
                enableInteractiveSelection: false,
                showCursor: false,
                style: const TextStyle(color: Colors.transparent, height: 1),
                cursorColor: Colors.transparent,
                decoration: null,
              ),
            ),
          ),
          AnimatedBuilder(
            animation: Listenable.merge([controller, focusNode]),
            builder: (context, _) {
              final value = controller.text;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => focusNode.requestFocus(),
                child: Row(
                  children: [
                    for (int i = 0; i < length; i++) ...[
                      Expanded(
                        child: _OtpCell(
                          char: i < value.length ? value[i] : '',
                          isFocused: focusNode.hasFocus && i == value.length,
                          isFilled: i < value.length,
                          hasError: hasError,
                        ),
                      ),
                      if (i < length - 1) const SizedBox(width: 10),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _OtpCell extends StatelessWidget {
  const _OtpCell({
    required this.char,
    required this.isFocused,
    required this.isFilled,
    required this.hasError,
  });

  final String char;
  final bool isFocused;
  final bool isFilled;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final borderColor = hasError
        ? AppColors.error
        : isFocused
        ? AppColors.primary
        : isFilled
        ? AppColors.textHint
        : AppColors.border;
    final bgColor = hasError
        ? AppColors.error.withValues(alpha: 0.06)
        : isFocused
        ? AppColors.primary.withValues(alpha: 0.08)
        : AppColors.surface;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
          width: isFocused || hasError ? 1.6 : 1,
        ),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 130),
        transitionBuilder: (child, anim) => ScaleTransition(
          scale: anim,
          child: FadeTransition(opacity: anim, child: child),
        ),
        child: char.isEmpty
            ? _CursorDot(key: const ValueKey('empty'), visible: isFocused)
            : Text(
                char,
                key: ValueKey(char + isFilled.toString()),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
      ),
    );
  }
}

class _CursorDot extends StatefulWidget {
  const _CursorDot({super.key, required this.visible});
  final bool visible;

  @override
  State<_CursorDot> createState() => _CursorDotState();
}

class _CursorDotState extends State<_CursorDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();
    return FadeTransition(
      opacity: _ctrl,
      child: Container(
        width: 2,
        height: 22,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
