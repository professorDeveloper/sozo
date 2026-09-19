import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/home/domain/usecase/home_usecase.dart';

import 'home_event.dart';
import 'home_state.dart';

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  final HomeUseCase useCase;

  /// Which load is the current one.
  ///
  /// Eleven places add [HomeLoad]: the page mounting, the shell seeing its first
  /// provider, the source being changed from anywhere in the app, two
  /// pull-to-refreshes, two Retry buttons and two Cloudflare solves. Bloc's
  /// default transformer runs them concurrently, so two of those overlap
  /// routinely — and the one that EMITS is whichever provider's backend answers
  /// last, not whichever the viewer picked last. Switching source twice in
  /// quick succession landed on the first source's rows, and a Retry that
  /// arrived while a refresh was still out repainted the error it had just
  /// cleared.
  ///
  /// Only one place could ever fix that, which is here where they all meet. The
  /// newest load wins; an older one still runs to completion but is not allowed
  /// to speak. Same pattern, and for the same reason, as SearchBloc's run token.
  int _runToken = 0;

  HomeBloc({required this.useCase}) : super(HomeInitial()) {
    on<HomeLoad>(_onHomeLoad);
  }

  Future<void> _onHomeLoad(HomeLoad event, Emitter<HomeState> emit) async {
    final token = ++_runToken;
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
    if (token != _runToken) return;
    debugPrint(
      '[HomeBloc] home: ${result.isSuccess ? 'ok' : 'fail: ${result.getErrorOrNull()}'}',
    );
    switch (result) {
      case Success(:final value):
        debugPrint(
          '[HomeBloc] banner=${value.banner.length} sections=${value.sections.length}',
        );
        final genreResult = await useCase.callGenres();
        // Checked again: the genres round-trip is a second window for a newer
        // load to have started, and this one is about to emit the rows that go
        // with the provider that was current when it began.
        if (token != _runToken) return;
        debugPrint(
          '[HomeBloc] genres: ${genreResult.isSuccess ? 'ok (${genreResult.getOrNull()?.length})' : 'fail'}',
        );
        emit(HomeLoaded(genreResult.getOrNull() ?? [], value));
      case Failure(:final error):
        emit(HomeError(error.toString()));
    }
  }
}
