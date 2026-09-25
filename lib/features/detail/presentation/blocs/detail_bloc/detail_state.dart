part of 'detail_bloc.dart';

abstract class DetailState {
  const DetailState();
}

class DetailInitial extends DetailState {
  const DetailInitial();
}

class DetailLoading extends DetailState {
  const DetailLoading();
}

class DetailLoaded extends DetailState {
  final DetailEntity detail;

  /// Set when the title was opened from a catalogue and this is the source
  /// that was found for it. The page names it under Play.
  final CatalogueLink? via;

  /// The source search is still running, so a null [via] does not yet mean
  /// there is no source.
  ///
  /// The page renders the catalogue's own record as soon as it has it rather
  /// than waiting for both, which is what makes this state exist at all. Without
  /// it, "nothing found" and "still looking" are the same page — so every
  /// catalogue title would show a Find a source button for a second or two and
  /// then replace it with Play.
  final bool resolving;

  /// Built from the copy saved with the downloads, because the source could
  /// not be reached.
  final bool offline;
  const DetailLoaded(
    this.detail, {
    this.via,
    this.resolving = false,
    this.offline = false,
  });
}

class DetailError extends DetailState {
  final String message;
  const DetailError(this.message);
}
