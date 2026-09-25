/// One screen of the setup.
enum OnboardingStep {
  welcome,
  language,
  kinds,
  genres,
  account,
  import,
  notifications,
  badges,
  widgets,
  done;

  String get path => this == welcome ? '/onboarding' : '/onboarding/$name';

  static OnboardingStep? fromName(String? name) {
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

/// Which setup is running.
enum OnboardingFlow {
  /// A new install, from the carousel to Home.
  firstRun,

  /// Settings → Personalize: taste, import and notifications again.
  personalize,

  /// A household profile that was just created: taste only.
  profile;

  List<OnboardingStep> get steps => switch (this) {
    firstRun => OnboardingStep.values,
    personalize => const [
      OnboardingStep.kinds,
      OnboardingStep.genres,
      OnboardingStep.import,
      OnboardingStep.notifications,
      OnboardingStep.widgets,
      OnboardingStep.done,
    ],
    profile => const [
      OnboardingStep.kinds,
      OnboardingStep.genres,
      OnboardingStep.done,
    ],
  };

  static OnboardingFlow fromName(String? name) {
    for (final f in values) {
      if (f.name == name) return f;
    }
    return firstRun;
  }
}

/// What decides whether a step is shown, as of now.
class OnboardingConditions {
  const OnboardingConditions({
    required this.signedIn,
    required this.hasKinds,
    this.notificationsSupported = false,
    this.notificationsGranted = false,
    this.widgetsSupported = false,
  });

  final bool signedIn;
  final bool hasKinds;
  final bool notificationsSupported;
  final bool notificationsGranted;

  /// Home-screen widgets exist here: an Android phone.
  final bool widgetsSupported;
}

bool isStepAvailable(OnboardingStep step, OnboardingConditions c) =>
    switch (step) {
      OnboardingStep.genres => c.hasKinds,
      OnboardingStep.account => !c.signedIn,
      OnboardingStep.import => c.signedIn,
      OnboardingStep.notifications =>
        c.notificationsSupported && !c.notificationsGranted,
      OnboardingStep.widgets => c.widgetsSupported,
      _ => true,
    };

/// The step after [current] in [flow], skipping what does not apply.
OnboardingStep? stepAfter(
  OnboardingFlow flow,
  OnboardingStep current,
  OnboardingConditions c,
) {
  final steps = flow.steps;
  final i = steps.indexOf(current);
  for (var j = i + 1; j < steps.length; j++) {
    if (isStepAvailable(steps[j], c)) return steps[j];
  }
  return null;
}

/// The step before [current], or null at the start of the flow.
OnboardingStep? stepBefore(
  OnboardingFlow flow,
  OnboardingStep current,
  OnboardingConditions c,
) {
  final steps = flow.steps;
  final i = steps.indexOf(current);
  for (var j = i - 1; j >= 0; j--) {
    if (isStepAvailable(steps[j], c)) return steps[j];
  }
  return null;
}

/// How far through the flow [current] is, 0 to 1.
double flowProgress(
  OnboardingFlow flow,
  OnboardingStep current,
  OnboardingConditions c,
) {
  final shown = [
    for (final s in flow.steps)
      if (s == current || isStepAvailable(s, c)) s,
  ];
  if (shown.length < 2) return 1;
  return shown.indexOf(current).clamp(0, shown.length - 1) / (shown.length - 1);
}
