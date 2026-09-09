import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/player_controls_layout.dart';
import 'package:soplay/features/detail/presentation/pages/player_controls_page.dart';

void main() {
  test('every control in the catalogue has its own icon', () {
    // The icon map lives in the presentation layer because an IconData is
    // Flutter and the catalogue is domain code. That split means a control can
    // be added to one and not the other, and the result is not an error — it is
    // a blank circle on the bar and in the editor, which reads as a broken
    // build rather than a missing entry.
    final fallback = iconForControl('__definitely_not_a_control__');
    final missing = <String>[];
    final seen = <IconData, String>{};
    final duplicated = <String>[];

    for (final spec in PlayerControlCatalogue.all) {
      final icon = iconForControl(spec.id);
      if (icon == fallback) missing.add(spec.id);
      final previous = seen[icon];
      if (previous != null) {
        duplicated.add('${spec.id} shares an icon with $previous');
      }
      seen[icon] = spec.id;
    }

    expect(missing, isEmpty, reason: 'these would render as a blank circle');
    // Two controls wearing the same glyph is a bar the viewer cannot read.
    expect(duplicated, isEmpty);
  });
}
