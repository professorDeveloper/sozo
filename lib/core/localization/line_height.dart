import 'package:flutter/widgets.dart';

/// A tight [height] for one line of text, with room for Vietnamese where needed.
///
/// A Vietnamese capital carries two marks, as in Ẳ or Ấ, and reaches about 1.03 em
/// above the baseline. Text cut off with an ellipsis is clipped to its line box, so
/// at a height of 1.08 a long title loses those marks, which makes it a different
/// word. Other languages keep the height the design chose.
double lineHeightFor(BuildContext context, double height) {
  final vietnamese = Localizations.maybeLocaleOf(context)?.languageCode == 'vi';
  return vietnamese && height < _vietnamese ? _vietnamese : height;
}

const double _vietnamese = 1.25;
