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
  const DetailLoaded(this.detail, {this.via});
}

class DetailError extends DetailState {
  final String message;
  const DetailError(this.message);
}
