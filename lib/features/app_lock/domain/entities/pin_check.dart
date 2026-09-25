import 'package:equatable/equatable.dart';

enum PinCheck {
  /// The PIN was right.
  ok,

  /// The PIN was wrong; [PinCheckResult.attemptsLeft] more are allowed before
  /// a wait is imposed.
  wrong,

  /// Too many wrong guesses; nothing is checked before [PinCheckResult.retryAt].
  lockedOut,

  /// The stored PIN cannot be read, so no PIN can be accepted. The lock
  /// screen offers the reset path instead of opening.
  unavailable,
}

class PinCheckResult extends Equatable {
  const PinCheckResult._(this.outcome, {this.retryAt, this.attemptsLeft = 0});

  const PinCheckResult.ok() : this._(PinCheck.ok);

  const PinCheckResult.wrong(int attemptsLeft)
    : this._(PinCheck.wrong, attemptsLeft: attemptsLeft);

  const PinCheckResult.lockedOut(DateTime retryAt)
    : this._(PinCheck.lockedOut, retryAt: retryAt);

  const PinCheckResult.unavailable() : this._(PinCheck.unavailable);

  final PinCheck outcome;
  final DateTime? retryAt;
  final int attemptsLeft;

  bool get isOk => outcome == PinCheck.ok;

  @override
  List<Object?> get props => [outcome, retryAt, attemptsLeft];
}
