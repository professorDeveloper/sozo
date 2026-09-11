import 'package:equatable/equatable.dart';

abstract class AppLockEvent extends Equatable {
  const AppLockEvent();
  @override
  List<Object?> get props => const [];
}

class AppLockStarted extends AppLockEvent {
  const AppLockStarted();
}

class AppLockPinLengthChosen extends AppLockEvent {
  const AppLockPinLengthChosen(this.length);
  final int length;
  @override
  List<Object?> get props => [length];
}

class AppLockPinDigitPressed extends AppLockEvent {
  const AppLockPinDigitPressed(this.digit);
  final String digit;
  @override
  List<Object?> get props => [digit];
}

class AppLockPinBackspacePressed extends AppLockEvent {
  const AppLockPinBackspacePressed();
}

class AppLockResetEntry extends AppLockEvent {
  const AppLockResetEntry();
}

class AppLockBiometricRequested extends AppLockEvent {
  const AppLockBiometricRequested(this.reason);
  final String reason;
  @override
  List<Object?> get props => [reason];
}

class AppLockToggleBiometric extends AppLockEvent {
  const AppLockToggleBiometric(this.enabled);
  final bool enabled;
  @override
  List<Object?> get props => [enabled];
}

class AppLockDisableRequested extends AppLockEvent {
  const AppLockDisableRequested();
}

/// Fired by the bloc itself when a lockout's wait is over.
class AppLockLockoutEnded extends AppLockEvent {
  const AppLockLockoutEnded();
}

/// "Forgot PIN": wipe the private list and switch the lock off.
class AppLockResetRequested extends AppLockEvent {
  const AppLockResetRequested();
}
