part of 'detail_bloc.dart';

abstract class DetailEvent {
  const DetailEvent();
}

class DetailLoad extends DetailEvent {
  final String contentUrl;
  final String? provider;

  /// What the card already knew — title, year, category. A catalogue title is
  /// resolved to a source by searching for its name, and the name lives here.
  final MovieEntity? hint;
  const DetailLoad(this.contentUrl, {this.provider, this.hint});
}
