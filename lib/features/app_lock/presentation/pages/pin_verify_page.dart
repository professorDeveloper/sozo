import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/app_lock/domain/repositories/app_lock_repository.dart';
import 'package:soplay/features/app_lock/presentation/bloc/app_lock_bloc.dart';
import 'package:soplay/features/app_lock/presentation/bloc/app_lock_event.dart';
import 'package:soplay/features/app_lock/presentation/bloc/app_lock_state.dart';
import 'package:soplay/features/app_lock/presentation/widgets/pin_dots.dart';
import 'package:soplay/features/app_lock/presentation/widgets/pin_keypad.dart';

class PinVerifyPage extends StatelessWidget {
  const PinVerifyPage({super.key, this.redirectTo = '/main'});

  final String redirectTo;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AppLockBloc(
        repository: getIt<AppLockRepository>(),
        mode: AppLockMode.verify,
      )..add(const AppLockStarted()),
      child: _PinVerifyView(redirectTo: redirectTo),
    );
  }
}

class _PinVerifyView extends StatefulWidget {
  const _PinVerifyView({required this.redirectTo});
  final String redirectTo;

  @override
  State<_PinVerifyView> createState() => _PinVerifyViewState();
}

class _PinVerifyViewState extends State<_PinVerifyView> {
  bool _biometricTried = false;

  Future<void> _resetLock() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'app_lock.reset_title'.tr(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'app_lock.reset_body'.tr(),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: Text(
              'general.cancel'.tr(),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: Text(
              'app_lock.reset'.tr(),
              // This wipes the user's PIN — the same weight of action as the
              // app's other error-coloured confirmations.
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await getIt<AppLockRepository>().disable();
    if (!mounted) return;
    context.go(widget.redirectTo);
  }

  void _maybeAutoBiometric(AppLockState state) {
    if (_biometricTried) return;
    if (!state.biometricAvailable || !state.biometricPreferred) return;
    _biometricTried = true;
    context.read<AppLockBloc>().add(
          AppLockBiometricRequested('app_lock.biometric_unlock_reason'.tr()),
        );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: BlocConsumer<AppLockBloc, AppLockState>(
        listenWhen: (a, b) =>
            a.stage != b.stage ||
            a.biometricAvailable != b.biometricAvailable ||
            a.biometricPreferred != b.biometricPreferred,
        listener: (context, state) {
          if (state.stage == AppLockStage.done) {
            context.go(widget.redirectTo);
            return;
          }
          _maybeAutoBiometric(state);
        },
        builder: (context, state) {
          final bloc = context.read<AppLockBloc>();
          return Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.lock_rounded,
                        color: AppColors.primary,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'app_lock.verify_title'.tr(),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'app_lock.verify_subtitle'.tr(),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 32),
                    PinDots(
                      length: state.pinLength,
                      filled: state.entered.length,
                      errorTick: state.errorTick,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 22,
                      child: state.errorMessage != null
                          ? Text(
                              state.errorMessage!.tr(),
                              style: const TextStyle(
                                color: AppColors.error,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          : null,
                    ),
                    const Spacer(),
                    PinKeypad(
                      onDigit: (d) =>
                          bloc.add(AppLockPinDigitPressed(d)),
                      onBackspace: () =>
                          bloc.add(const AppLockPinBackspacePressed()),
                      onBiometric:
                          state.biometricAvailable && state.biometricPreferred
                              ? () => bloc.add(AppLockBiometricRequested(
                                    'app_lock.biometric_unlock_reason'.tr(),
                                  ))
                              : null,
                    ),
                    if (isDesktopPlatform)
                      TextButton(
                        onPressed: _resetLock,
                        child: Text(
                          'app_lock.forgot_pin'.tr(),
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
