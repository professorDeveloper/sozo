import 'package:flutter/widgets.dart';

/// A tight [height] for one line of text, with room for marks where needed.
///
/// A Vietnamese capital carries two marks, as in Ẳ or Ấ, and reaches about 1.03 em
/// above the baseline. Devanagari has marks on both sides of the line, as in कहानियाँ
/// and हूँ. Text cut off with an ellipsis is clipped to its line box, so at a height
/// of 1.08 a long title loses those marks, which makes it a different word. Other
/// languages keep the height the design chose.
double lineHeightFor(BuildContext context, double height) {
  final code = Localizations.maybeLocaleOf(context)?.languageCode;
  return _needsRoom.contains(code) && height < _roomy ? _roomy : height;
}

const Set<String> _needsRoom = {'vi', 'hi'};
const double _roomy = 1.25;
