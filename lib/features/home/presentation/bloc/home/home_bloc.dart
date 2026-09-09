import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/home/domain/usecase/home_usecase.dart';

import 'home_event.dart';
import 'home_state.dart';

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  final HomeUseCase useCase;

  HomeBloc({required this.useCase}) : super(HomeInitial()) {
    on<HomeLoad>(_onHomeLoad);
  }

  Future<void> _onHomeLoad(HomeLoad event, Emitter<HomeState> emit) async {
    if (!event.silent || state is! HomeLoaded) {
      emit(HomeLoading());
    }

    // Catalog first, genres only if it arrived.
    //
    // The order used to be the other way round, which meant a provider whose
    // catalog is down still paid for a genres round-trip on every load — and
    // the genres endpoint answers from a static list, so it cheerfully returned
    // 18 of them for a source that could not produce a single title. Nothing
    // rendered them, because a failed catalog emits [HomeError], but the app was
    // still asking a question whose answer it had already decided to throw away.
    final result = await useCase();
    debugPrint('[HomeBloc] home: ${result.isSuccess ? 'ok' : 'fail: ${result.getErrorOrNull()}'}');
    switch (result) {
      case Success(:final value):
        debugPrint('[HomeBloc] banner=${value.banner.length} sections=${value.sections.length}');
        final genreResult = await useCase.callGenres();
        debugPrint('[HomeBloc] genres: ${genreResult.isSuccess ? 'ok (${genreResult.getOrNull()?.length})' : 'fail'}');
        emit(HomeLoaded(genreResult.getOrNull() ?? [], value));
      case Failure(:final error):
        emit(HomeError(error.toString()));
    }
  }
}
