import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/playback/lock_pill.dart';

Duration s(num v) => Duration(milliseconds: (v * 1000).round());

void main() {
  test('the pill fades 3 s after it is shown', () {
    final pill = LockPill()..show(s(0));
    expect(pill.isVisible(s(2.9)), isTrue);
    expect(pill.isVisible(s(3)), isFalse);
    expect(pill.hidesAt(), s(3));
  });

  test('a tap brings it back for another 3 s', () {
    final pill = LockPill()..show(s(0));
    pill.show(s(10));
    expect(pill.isVisible(s(12)), isTrue);
    expect(pill.isVisible(s(13.1)), isFalse);
  });

  test('a tap on the visible pill unlocks', () {
    final pill = LockPill()..show(s(0));
    expect(pill.tapPill(s(1)), isTrue);
    expect(pill.isVisible(s(1)), isFalse);
  });

  test('a tap where the faded pill was only shows it', () {
    final pill = LockPill()..show(s(0));
    expect(pill.tapPill(s(5)), isFalse);
    expect(pill.isVisible(s(5.5)), isTrue);
    expect(pill.tapPill(s(6)), isTrue);
  });
}
