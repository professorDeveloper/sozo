import 'package:flutter/foundation.dart';

/// Everything that identifies one title's trailer, in one value.
///
/// The button and the header preview are on screen together for the same
/// title and both ask the same service for it, so what they ask WITH has to be
/// a single value rather than two argument lists assembled separately. Two
/// lists drift; a lookup keyed on a slightly different string is a second
/// network call for one answer, and on a remake it can be a different film.
///
/// It carries [==] because the detail header is rebuilt on every scroll frame:
/// the preview compares the incoming query with the one it started on, and
/// identity comparison would make each frame look like a new title and tear
/// the playing trailer down.
@immutable
class TrailerQuery {
  const TrailerQuery({
    required this.title,
    required this.year,
    required this.isSerial,
    this.youtubeId,
  });

  /// The video the catalogue already named. Non-null only for the TMDB-backed
  /// providers; for everything else the title is all there is to go on.
  final String? youtubeId;

  final String title;

  /// Narrows a name shared by an original and its remake. Optional because
  /// plenty of providers do not publish one.
  final int? year;

  /// Decides whether the search runs over films or series. A film and the
  /// series adaptation of the same book are two different trailers.
  final bool isSerial;

  @override
  bool operator ==(Object other) =>
      other is TrailerQuery &&
      other.youtubeId == youtubeId &&
      other.title == title &&
      other.year == year &&
      other.isSerial == isSerial;

  @override
  int get hashCode => Object.hash(youtubeId, title, year, isSerial);
}
