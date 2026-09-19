import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/detail/domain/entities/playback_entity.dart';
import 'package:soplay/features/detail/domain/usecases/get_episodes_usecase.dart';

part 'episodes_event.dart';
part 'episodes_state.dart';

class EpisodesBloc extends Bloc<EpisodesEvent, EpisodesState> {
  final GetEpisodesUseCase useCase;

  EpisodesBloc({required this.useCase}) : super(const EpisodesInitial()) {
    on<EpisodesLoad>(_onLoad);
    on<EpisodesReset>((_, emit) => emit(const EpisodesInitial()));
  }

  Future<void> _onLoad(EpisodesLoad event, Emitter<EpisodesState> emit) async {
    emit(const EpisodesLoading());
    final result = await useCase(event.contentUrl, provider: event.provider);
    switch (result) {
      case Success(:final value):
        emit(EpisodesLoaded(value));
      case Failure(:final error):
        emit(EpisodesError(error.toString().replaceFirst('Exception: ', '')));
    }
  }
}
