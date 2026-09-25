import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/detail/domain/entities/playback_entity.dart';
import 'package:soplay/features/detail/domain/usecases/get_episodes_usecase.dart';
import 'package:soplay/features/download/domain/repositories/offline_title_repository.dart';

part 'episodes_event.dart';
part 'episodes_state.dart';

class EpisodesBloc extends Bloc<EpisodesEvent, EpisodesState> {
  final GetEpisodesUseCase useCase;
  final OfflineTitleRepository? offline;
  final Future<bool> Function()? isOffline;

  EpisodesBloc({required this.useCase, this.offline, this.isOffline})
    : super(const EpisodesInitial()) {
    on<EpisodesLoad>(_onLoad);
    on<EpisodesReset>((_, emit) => emit(const EpisodesInitial()));
  }

  Future<void> _onLoad(EpisodesLoad event, Emitter<EpisodesState> emit) async {
    emit(const EpisodesLoading());
    final saved = offline?.get(event.contentUrl);
    final usable = saved != null && saved.episodes.isNotEmpty ? saved : null;
    if (usable != null && await (isOffline?.call() ?? Future.value(false))) {
      emit(EpisodesLoaded(usable.toPlayback(), offline: true));
      return;
    }
    final result = await useCase(event.contentUrl, provider: event.provider);
    switch (result) {
      case Success(:final value):
        emit(EpisodesLoaded(value));
        await offline?.noteEpisodes(value, contentUrl: event.contentUrl);
      case Failure(:final error):
        if (usable != null) {
          emit(EpisodesLoaded(usable.toPlayback(), offline: true));
          return;
        }
        emit(EpisodesError(error.toString().replaceFirst('Exception: ', '')));
    }
  }
}
