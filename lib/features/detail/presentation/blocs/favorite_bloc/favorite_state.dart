import 'package:equatable/equatable.dart';

sealed class FavoriteState extends Equatable {
  const FavoriteState();

  @override
  List<Object?> get props => [];
}

class FavoriteInitial extends FavoriteState {
  const FavoriteInitial();
}

class FavoriteReady extends FavoriteState {
  const FavoriteReady({
    required this.isInList,
    this.isLoading = false,
    this.inPrivate = false,
  });

  final bool isInList;
  final bool isLoading;

  final bool inPrivate;

  FavoriteReady copyWith({bool? isInList, bool? isLoading, bool? inPrivate}) =>
      FavoriteReady(
        isInList: isInList ?? this.isInList,
        isLoading: isLoading ?? this.isLoading,
        inPrivate: inPrivate ?? this.inPrivate,
      );

  @override
  List<Object?> get props => [isInList, isLoading, inPrivate];
}
