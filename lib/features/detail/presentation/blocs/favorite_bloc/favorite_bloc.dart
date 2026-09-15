import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/my_list/data/datasources/my_list_local_data_source.dart';
import 'package:soplay/features/my_list/data/private_list_service.dart';
import 'package:soplay/features/my_list/domain/entities/favorite_entity.dart';
import 'package:soplay/features/my_list/domain/usecases/add_favorite_usecase.dart';
import 'package:soplay/features/my_list/domain/usecases/remove_favorite_usecase.dart';

import 'favorite_event.dart';
import 'favorite_state.dart';

class FavoriteBloc extends Bloc<FavoriteEvent, FavoriteState> {
  FavoriteBloc({
    required AddFavoriteUseCase addFavorite,
    required RemoveFavoriteUseCase removeFavorite,
    required MyListLocalDataSource local,
  }) : _addFavorite = addFavorite,
       _removeFavorite = removeFavorite,
       _local = local,
       super(const FavoriteInitial()) {
    on<FavoriteLoad>(_onLoad);
    on<FavoriteToggle>(_onToggle);
  }

  final AddFavoriteUseCase _addFavorite;
  final RemoveFavoriteUseCase _removeFavorite;
  final MyListLocalDataSource _local;

  Future<void> _onLoad(FavoriteLoad event, Emitter<FavoriteState> emit) async {
    final inPrivate = getIt<PrivateListService>().contains(event.contentUrl);
    final isIn =
        _local.isFavorite(event.provider, event.contentUrl) ||
        (event.isFavorited ?? false);
    emit(FavoriteReady(isInList: isIn || inPrivate, inPrivate: inPrivate));
  }

  Future<void> _onToggle(
    FavoriteToggle event,
    Emitter<FavoriteState> emit,
  ) async {
    final current = state;
    if (current is! FavoriteReady || current.isLoading) return;
    // A title in the private list reads as "in the list" (see _onLoad), and
    // toggling it used to call removeFavorite — which removes from My List,
    // where it is not — then report it as in no list at all while it sat in
    // the private one. The private list has its own actions, behind the PIN.
    if (current.inPrivate) return;

    final nextIsInList = !current.isInList;
    emit(current.copyWith(isInList: nextIsInList, isLoading: true));

    if (current.isInList) {
      final result = await _removeFavorite(event.contentUrl);
      switch (result) {
        case Success():
          emit(current.copyWith(isInList: nextIsInList, isLoading: false));
        case Failure():
          emit(current.copyWith(isLoading: false));
      }
    } else {
      final result = await _addFavorite(
        FavoriteEntity(
          contentUrl: event.contentUrl,
          provider: event.provider,
          title: event.title,
          thumbnail: event.thumbnail,
        ),
      );
      switch (result) {
        case Success():
          emit(current.copyWith(isInList: nextIsInList, isLoading: false));
        case Failure():
          emit(current.copyWith(isLoading: false));
      }
    }
  }
}
