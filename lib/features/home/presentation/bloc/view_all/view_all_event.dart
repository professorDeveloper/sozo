import 'package:equatable/equatable.dart' show Equatable;

class ViewAllEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class ViewAllLoadMore extends ViewAllEvent {
  /// From the retry footer: skips the backoff a failed page imposes on the
  /// scroll-driven requests.
  final bool retry;

  ViewAllLoadMore({this.retry = false});

  @override
  List<Object?> get props => [retry];
}

class ViewAllLoad extends ViewAllEvent {
  final String? slug;
  final String key;

  ViewAllLoad({this.slug, required this.key});

  @override
  List<Object?> get props => [slug, key];
}
