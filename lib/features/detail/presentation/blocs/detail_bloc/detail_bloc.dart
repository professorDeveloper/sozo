import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/detail/domain/entities/detail_entity.dart';
import 'package:soplay/features/detail/domain/services/catalogue_resolver.dart';
import 'package:soplay/features/detail/domain/usecases/get_detail_usecase.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';

part 'detail_event.dart';
part 'detail_state.dart';

class DetailBloc extends Bloc<DetailEvent, DetailState> {
  final GetDetailUseCase useCase;

  /// Null only in tests that never open a catalogue title.
  final CatalogueResolver? resolver;

  DetailBloc({required this.useCase, this.resolver})
    : super(const DetailInitial()) {
    on<DetailLoad>(_onLoad);
  }

  Future<void> _onLoad(DetailLoad event, Emitter<DetailState> emit) async {
    emit(const DetailLoading());

    var contentUrl = event.contentUrl;
    var provider = event.provider;
    CatalogueLink? via;

    // A catalogue title has no page of its own to load. Find the source that
    // carries it first, then load THAT page; the rest of the bloc, and the
    // page above it, never learn that the title came from a catalogue.
    if (Catalogue.isId(provider)) {
      final resolver = this.resolver;
      if (resolver == null) {
        emit(const DetailError('catalogue.no_resolver'));
        return;
      }
      via = await resolver.resolve(
        catalogueId: provider!,
        contentUrl: contentUrl,
        hint: event.hint,
      );
      if (via == null) {
        emit(const DetailError('catalogue.no_source'));
        return;
      }
      contentUrl = via.contentUrl;
      provider = via.providerId;
    }

    final result = await useCase(contentUrl, provider: provider);
    switch (result) {
      case Success(:final value):
        emit(DetailLoaded(value, via: via));
      case Failure(:final error):
        // A remembered link that no longer loads should not be tried again
        // next time: the source may have moved the title or dropped it.
        if (via != null) {
          await resolver?.forget(event.provider!, event.contentUrl);
        }
        emit(DetailError(error.toString().replaceFirst('Exception: ', '')));
    }
  }
}
