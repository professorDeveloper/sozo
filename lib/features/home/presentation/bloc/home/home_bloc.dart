import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/home/domain/entities/home_data_entity.dart';
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

  /// Which source a load is for. Null in tests that do not care, and then
  /// nothing is cached.
  final String Function()? currentProvider;

  /// The last Home each source produced, newest last.
  ///
  /// Switching Watch → Manga → Watch reloaded Watch's Home from the network
  /// behind a skeleton, for rows the app had shown seconds earlier. A source
  /// that has been shown recently now comes back at once and refreshes
  /// underneath.
  final Map<String, ({DateTime at, HomeLoaded home})> _recent = {};
  static const int _recentLimit = 6;
  static const Duration _recentFor = Duration(hours: 2);

  HomeBloc({required this.useCase, this.currentProvider})
    : super(HomeInitial()) {
    on<HomeLoad>(_onHomeLoad);
  }

  /// The catalogue load already asking a source, joined rather than repeated.
  ///
  /// A mode switch, a source pick and a rail change can each ask for Home in
  /// the same moment; they used to become three identical requests — and for
  /// an extension source, three calls queued one behind another in its
  /// runtime, so the Home the viewer waited for took three times as long.
  Future<Result<HomeDataEntity>>? _inflight;
  String? _inflightFor;

  Future<Result<HomeDataEntity>> _catalogueFor(String provider) {
    final running = _inflight;
    if (running != null && provider.isNotEmpty && _inflightFor == provider) {
      return running;
    }
    final call = useCase();
    _inflight = call;
    _inflightFor = provider;
    call.whenComplete(() {
      if (identical(_inflight, call)) {
        _inflight = null;
        _inflightFor = null;
      }
    });
    return call;
  }

  Future<void> _onHomeLoad(HomeLoad event, Emitter<HomeState> emit) async {
    final token = ++_runToken;
    final provider = currentProvider?.call() ?? '';
    final recent = provider.isEmpty ? null : _recent[provider];
    var showedRecent = false;
    if (recent != null &&
        DateTime.now().difference(recent.at) < _recentFor &&
        state != recent.home) {
      emit(recent.home);
      showedRecent = true;
    } else if (!event.silent || state is! HomeLoaded) {
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
    final result = await _catalogueFor(provider);
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
        final loaded = HomeLoaded(genreResult.getOrNull() ?? [], value);
        if (provider.isNotEmpty) {
          _recent.remove(provider);
          _recent[provider] = (at: DateTime.now(), home: loaded);
          if (_recent.length > _recentLimit) {
            _recent.remove(_recent.keys.first);
          }
        }
        emit(loaded);
      case Failure(:final error):
        // The rows just restored stay: a refresh that failed is not a reason
        // to replace a Home that was working a moment ago with an error.
        if (showedRecent) return;
        emit(HomeError(error.toString()));
    }
  }
}
