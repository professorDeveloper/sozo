// Correcting a wrong title has to take you to the thing you corrected.
//
// "Wrong title?" opens a search of that one source so the viewer can find the
// right entry by hand. They search, they read the results, they tap the one
// they meant — and the sheet's reply was a snackbar. The corrected row was
// redrawn behind it, and they had to find it and tap it a second time. On a
// serial that is two taps between somebody and the episode list they were
// already asking for.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sheet = File(
    'lib/features/detail/presentation/widgets/alternate_source_sheet.dart',
  ).readAsStringSync();

  String correctBody() {
    final start = sheet.indexOf('Future<void> _correct(');
    expect(start, greaterThan(-1));
    final end = sheet.indexOf('\n  @override', start);
    return sheet.substring(start, end > start ? end : sheet.length);
  }

  test('a correction opens it, it does not just announce itself', () {
    final body = correctBody();
    expect(body, contains('await _pick('));
  });

  test('through the same path an ordinary pick takes', () {
    // `_pick` is what turns a choice into PlayerArgs — including matching the
    // episode by NUMBER and saying so when the source has the show but not this
    // episode. A second, parallel way of opening a source would have to
    // re-learn all of that.
    final body = correctBody();
    expect(body, contains('AlternateSource('));
    expect(body, contains('provider: provider'));
    expect(body, contains('item: picked'));
  });

  test('and it is an exact match, without qualification', () {
    // Every other row carries a score because a machine guessed it. This one
    // was chosen by a person looking at the title.
    final body = correctBody();
    expect(body, contains('TitleConfidence.exact'));
  });

  test('the choice is still remembered before anything else happens', () {
    // Someone who backs out immediately still has the correction on disk.
    final body = correctBody();
    expect(
      body.indexOf('_choices.remember(choice)'),
      lessThan(body.indexOf('await _pick(')),
    );
  });

  test('and _pick still reports a source that lacks this episode', () {
    expect(sheet, contains("'player.alt_no_episode'.tr("));
  });
}
