import 'package:equatable/equatable.dart';

enum AppLockStage { chooseLength, enterNew, confirmNew, verify, done, disabled }

class AppLockState extends Equatable {
  const AppLockState({
    required this.stage,
    required this.pinLength,
    required this.entered,
    required this.firstPin,
    required this.biometricAvailable,
    required this.biometricPreferred,
    required this.errorTick,
    required this.errorMessage,
    required this.isProcessing,
    this.errorArgs = const [],
    this.retryAt,
    this.pinUnavailable = false,
  });

  factory AppLockState.initial() => const AppLockState(
    stage: AppLockStage.chooseLength,
    pinLength: 4,
    entered: '',
    firstPin: '',
    biometricAvailable: false,
    biometricPreferred: false,
    errorTick: 0,
    errorMessage: null,
    isProcessing: false,
  );

  final AppLockStage stage;
  final int pinLength;
  final String entered;
  final String firstPin;
  final bool biometricAvailable;
  final bool biometricPreferred;
  final int errorTick;
  final String? errorMessage;
  final bool isProcessing;

  /// Arguments for [errorMessage]'s translation.
  final List<String> errorArgs;

  /// While set and in the future, too many wrong PINs were entered and the
  /// keypad is ignored until then.
  final DateTime? retryAt;

  /// The stored PIN cannot be read, so no entry can succeed; the screen
  /// offers the reset path instead.
  final bool pinUnavailable;

  bool get isLockedOut => retryAt != null && retryAt!.isAfter(DateTime.now());

  AppLockState copyWith({
    AppLockStage? stage,
    int? pinLength,
    String? entered,
    String? firstPin,
    bool? biometricAvailable,
    bool? biometricPreferred,
    int? errorTick,
    String? errorMessage,
    bool clearError = false,
    bool? isProcessing,
    List<String>? errorArgs,
    DateTime? retryAt,
    bool clearRetryAt = false,
    bool? pinUnavailable,
  }) {
    return AppLockState(
      stage: stage ?? this.stage,
      pinLength: pinLength ?? this.pinLength,
      entered: entered ?? this.entered,
      firstPin: firstPin ?? this.firstPin,
      biometricAvailable: biometricAvailable ?? this.biometricAvailable,
      biometricPreferred: biometricPreferred ?? this.biometricPreferred,
      errorTick: errorTick ?? this.errorTick,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isProcessing: isProcessing ?? this.isProcessing,
      errorArgs: clearError ? const [] : (errorArgs ?? this.errorArgs),
      retryAt: clearRetryAt ? null : (retryAt ?? this.retryAt),
      pinUnavailable: pinUnavailable ?? this.pinUnavailable,
    );
  }

  @override
  List<Object?> get props => [
    stage,
    pinLength,
    entered,
    firstPin,
    biometricAvailable,
    biometricPreferred,
    errorTick,
    errorMessage,
    isProcessing,
    errorArgs,
    retryAt,
    pinUnavailable,
  ];
}
