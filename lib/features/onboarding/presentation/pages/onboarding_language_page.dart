import 'package:flutter/material.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/localization/app_language.dart';
import 'package:soplay/core/localization/language_picker.dart';
import 'package:soplay/features/onboarding/domain/onboarding_flow.dart';
import 'package:soplay/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:soplay/features/onboarding/presentation/onboarding_navigation.dart';
import 'package:soplay/features/onboarding/presentation/widgets/onboarding_scaffold.dart';

/// The language step: Settings' language page, inside the setup's chrome.
class OnboardingLanguagePage extends StatefulWidget {
  const OnboardingLanguagePage({super.key});

  @override
  State<OnboardingLanguagePage> createState() => _OnboardingLanguagePageState();
}

class _OnboardingLanguagePageState extends State<OnboardingLanguagePage> {
  final OnboardingController _c = getIt<OnboardingController>();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _c.arrive(OnboardingStep.language),
    );
  }

  Future<void> _continue(String code) async {
    if (_busy) return;
    _busy = true;
    await AppLanguage.set(context, code);
    if (mounted) await onboardingNext(context);
    _busy = false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onboardingBack(context);
      },
      child: LanguagePage(
        firstRun: true,
        header: OnboardingTopBar(
          progress: _c.progress,
          onBack: () => onboardingBack(context),
        ),
        onContinue: _continue,
      ),
    );
  }
}
