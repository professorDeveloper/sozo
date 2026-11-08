import 'package:equatable/equatable.dart';

import '../../../domain/entities/movie.dart';

class ViewAllState extends Equatable {
  @override
  List<Object?> get props => [];
}

class ViewAllInitial extends ViewAllState {}

class ViewAllLoading extends ViewAllState {}

class ViewAllError extends ViewAllState {
  final String mesage;

  ViewAllError({required this.mesage});

  @override
  List<Object?> get props => [mesage];
}

class ViewAllLoaded extends ViewAllState {
  final List<MovieEntity> items;
  final int currentPage;
  final int totalPages;
  final bool isLoadingMore;

  /// The last next-page request failed; the grid shows a retry footer.
  final bool loadMoreFailed;

  bool get hasMore => currentPage < totalPages;

  ViewAllLoaded({
    required this.items,
    required this.currentPage,
    required this.totalPages,
    this.isLoadingMore = false,
    this.loadMoreFailed = false,
  });

  @override
  List<Object?> get props => [
    items,
    currentPage,
    totalPages,
    isLoadingMore,
    loadMoreFailed,
  ];
}
