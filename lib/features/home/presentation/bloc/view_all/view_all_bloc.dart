import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart' show Bloc, Emitter;
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/home/domain/entities/view_all_paging_entity.dart';
import 'package:soplay/features/home/presentation/bloc/view_all/view_all_event.dart';
import 'package:soplay/features/home/presentation/bloc/view_all/view_all_state.dart';

import '../../../domain/usecase/view_all_usecase.dart';

class ViewAllBloc extends Bloc<ViewAllEvent, ViewAllState> {
  final ViewAllUseCase useCase;
  final DateTime Function() _now;
  String _key = '';
  String _slug = '';

  /// Consecutive failed next-page requests, and when the scroll may try again.
  int _failures = 0;
  DateTime? _retryAfter;

  static const Duration firstBackoff = Duration(seconds: 2);
  static const Duration maxBackoff = Duration(seconds: 60);

  static Duration backoffFor(int failures) {
    if (failures <= 0) return Duration.zero;
    final ms = firstBackoff.inMilliseconds * math.pow(2, failures - 1);
    return Duration(
      milliseconds: math.min(ms.toInt(), maxBackoff.inMilliseconds),
    );
  }

  ViewAllBloc({required this.useCase, DateTime Function()? now})
    : _now = now ?? DateTime.now,
      super(ViewAllInitial()) {
    on<ViewAllLoad>(_onLoad);
    on<ViewAllLoadMore>(_onLoadMore);
  }

  Future<void> _onLoad(ViewAllLoad event, Emitter<ViewAllState> emit) async {
    _key = event.key;
    _slug = event.slug ?? '';
    _failures = 0;
    _retryAfter = null;
    emit(ViewAllLoading());

    final Result<ViewAllPagingEntity> result = await useCase(_key, _slug, 1);
    if (result.isSuccess) {
      final data = result.getOrNull()!;
      emit(ViewAllLoaded(
        items: data.items,
        currentPage: data.page,
        totalPages: data.totalPages,
      ));
    } else {
      emit(ViewAllError(mesage: result.getErrorOrNull()!.toString()));
    }
  }

  Future<void> _onLoadMore(ViewAllLoadMore event, Emitter<ViewAllState> emit) async {
    final current = state;
    if (current is! ViewAllLoaded || !current.hasMore || current.isLoadingMore) return;
    // The scroll listener fires on every frame near the bottom. After a
    // failure those are refused until the backoff runs out; the footer's
    // retry is not.
    final wait = _retryAfter;
    if (!event.retry && wait != null && _now().isBefore(wait)) return;

    emit(ViewAllLoaded(
      items: current.items,
      currentPage: current.currentPage,
      totalPages: current.totalPages,
      isLoadingMore: true,
    ));

    final result = await useCase(_key, _slug, current.currentPage + 1);
    if (result.isSuccess) {
      _failures = 0;
      _retryAfter = null;
      final data = result.getOrNull()!;
      emit(ViewAllLoaded(
        items: [...current.items, ...data.items],
        currentPage: data.page,
        totalPages: data.totalPages,
      ));
    } else {
      // A failed append keeps the grid and scroll position; the footer says
      // what happened instead of a spinner that just disappears.
      _failures++;
      _retryAfter = _now().add(backoffFor(_failures));
      emit(ViewAllLoaded(
        items: current.items,
        currentPage: current.currentPage,
        totalPages: current.totalPages,
        loadMoreFailed: true,
      ));
    }
  }
}
