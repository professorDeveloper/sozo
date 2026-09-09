import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/app_lock/domain/repositories/app_lock_repository.dart';
import 'package:soplay/features/app_lock/presentation/bloc/app_lock_bloc.dart';
import 'package:soplay/features/app_lock/presentation/bloc/app_lock_event.dart';
import 'package:soplay/features/app_lock/presentation/bloc/app_lock_state.dart';
import 'package:soplay/features/app_lock/presentation/widgets/pin_dots.dart';
import 'package:soplay/features/app_lock/presentation/widgets/pin_keypad.dart';

class PrivateUnlockPage extends StatelessWidget {
  const PrivateUnlockPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AppLockBloc(
        repository: getIt<AppLockRepository>(),
        mode: AppLockMode.verify,
      )..add(const AppLockStarted()),
      child: const _PrivateUnlockView(),
    );
  }
}

class _PrivateUnlockView extends StatefulWidget {
  const _PrivateUnlockView();

  @override
  State<_PrivateUnlockView> createState() => _PrivateUnlockViewState();
}

class _PrivateUnlockViewState extends State<_PrivateUnlockView> {
  bool _biometricTried = false;

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
    return BlocConsumer<AppLockBloc, AppLockState>(
      listenWhen: (a, b) =>
          a.stage != b.stage ||
          a.biometricAvailable != b.biometricAvailable ||
          a.biometricPreferred != b.biometricPreferred,
      listener: (context, state) {
        if (state.stage == AppLockStage.done) {
          Navigator.of(context).pop(true);
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
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(start: 8),
                      child: IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.textPrimary,
                        ),
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
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
                    onDigit: (d) => bloc.add(AppLockPinDigitPressed(d)),
                    onBackspace: () =>
                        bloc.add(const AppLockPinBackspacePressed()),
                    onBiometric:
                        state.biometricAvailable && state.biometricPreferred
                            ? () => bloc.add(AppLockBiometricRequested(
                                  'app_lock.biometric_unlock_reason'.tr(),
                                ))
                            : null,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
