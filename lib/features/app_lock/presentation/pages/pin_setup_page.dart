import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/app_lock/domain/repositories/app_lock_repository.dart';
import 'package:soplay/features/app_lock/presentation/bloc/app_lock_bloc.dart';
import 'package:soplay/features/app_lock/presentation/bloc/app_lock_event.dart';
import 'package:soplay/features/app_lock/presentation/bloc/app_lock_state.dart';
import 'package:soplay/features/app_lock/presentation/widgets/pin_dots.dart';
import 'package:soplay/features/app_lock/presentation/widgets/pin_keypad.dart';

class PinSetupPage extends StatelessWidget {
  const PinSetupPage({super.key, this.changeMode = false});

  final bool changeMode;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AppLockBloc(
        repository: getIt<AppLockRepository>(),
        mode: changeMode ? AppLockMode.change : AppLockMode.setup,
      )..add(const AppLockStarted()),
      child: const _PinSetupView(),
    );
  }
}

class _PinSetupView extends StatelessWidget {
  const _PinSetupView();

  @override
  Widget build(BuildContext context) {
    return BlocListener<AppLockBloc, AppLockState>(
      listenWhen: (a, b) => a.stage != b.stage,
      listener: (context, state) {
        if (state.stage == AppLockStage.done) {
          if (context.canPop()) {
            context.pop(true);
          } else {
            context.go('/main');
          }
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text('app_lock.setup_title'.tr()),
        ),
        body: SafeArea(
          child: BlocBuilder<AppLockBloc, AppLockState>(
            builder: (context, state) {
              switch (state.stage) {
                case AppLockStage.verify:
                  return _VerifyForChange(state: state);
                case AppLockStage.chooseLength:
                  return const _ChooseLength();
                case AppLockStage.enterNew:
                case AppLockStage.confirmNew:
                  return _EnterNew(state: state);
                case AppLockStage.done:
                case AppLockStage.disabled:
                  return const SizedBox.shrink();
              }
            },
          ),
        ),
      ),
    );
  }
}

class _ChooseLength extends StatelessWidget {
  const _ChooseLength();

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<AppLockBloc>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'app_lock.choose_length_title'.tr(),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'app_lock.choose_length_subtitle'.tr(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 32),
          _LengthOption(
            length: 4,
            onTap: () => bloc.add(const AppLockPinLengthChosen(4)),
          ),
          const SizedBox(height: 12),
          _LengthOption(
            length: 6,
            onTap: () => bloc.add(const AppLockPinLengthChosen(6)),
          ),
        ],
      ),
    );
  }
}

class _LengthOption extends StatelessWidget {
  const _LengthOption({required this.length, required this.onTap});
  final int length;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Row(
            children: [
              Row(
                children: List.generate(
                  length,
                  (i) => Container(
                    margin: const EdgeInsetsDirectional.only(end: 6),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'app_lock.length_n_digits'.tr(args: ['$length']),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnterNew extends StatelessWidget {
  const _EnterNew({required this.state});
  final AppLockState state;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<AppLockBloc>();
    final isConfirm = state.stage == AppLockStage.confirmNew;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              isConfirm
                  ? 'app_lock.confirm_pin_title'.tr()
                  : 'app_lock.create_pin_title'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              isConfirm
                  ? 'app_lock.confirm_pin_subtitle'.tr()
                  : 'app_lock.create_pin_subtitle'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(height: 36),
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
            onBackspace: () => bloc.add(const AppLockPinBackspacePressed()),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _VerifyForChange extends StatelessWidget {
  const _VerifyForChange({required this.state});
  final AppLockState state;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<AppLockBloc>();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'app_lock.verify_current_pin'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
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
            onBackspace: () => bloc.add(const AppLockPinBackspacePressed()),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
