part of 'episodes_bloc.dart';

abstract class EpisodesState {
  const EpisodesState();
}

class EpisodesInitial extends EpisodesState {
  const EpisodesInitial();
}

class EpisodesLoading extends EpisodesState {
  const EpisodesLoading();
}

class EpisodesLoaded extends EpisodesState {
  final PlaybackEntity playback;

  /// The list saved with the downloads, because the source could not be
  /// reached.
  final bool offline;
  const EpisodesLoaded(this.playback, {this.offline = false});
}

class EpisodesError extends EpisodesState {
  final String message;
  const EpisodesError(this.message);
}
