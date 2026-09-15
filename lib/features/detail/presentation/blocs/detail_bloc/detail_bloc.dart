import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/anilist/data/anilist_api.dart';
import 'package:soplay/features/detail/domain/entities/detail_entity.dart';
import 'package:soplay/features/detail/domain/services/catalogue_detail.dart';
import 'package:soplay/features/detail/domain/services/catalogue_resolver.dart';
import 'package:soplay/features/detail/domain/usecases/get_detail_usecase.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';

part 'detail_event.dart';
part 'detail_state.dart';

class DetailBloc extends Bloc<DetailEvent, DetailState> {
  final GetDetailUseCase useCase;

  /// Null only in tests that never open a catalogue title.
  final CatalogueResolver? resolver;
  final AnilistApi? anilist;

  DetailBloc({required this.useCase, this.resolver, this.anilist})
    : super(const DetailInitial()) {
    on<DetailLoad>(_onLoad);
  }

  Future<void> _onLoad(DetailLoad event, Emitter<DetailState> emit) async {
    emit(const DetailLoading());

    final catalogue = Catalogue.fromId(event.provider);
    if (catalogue != null) {
      final resolver = this.resolver;
      if (resolver == null) {
        emit(const DetailError('catalogue.no_resolver'));
        return;
      }
      await _loadFromCatalogue(catalogue, event, resolver, emit);
      return;
    }

    final result = await useCase(event.contentUrl, provider: event.provider);
    switch (result) {
      case Success(:final value):
        emit(DetailLoaded(value));
      case Failure(:final error):
        emit(DetailError(error.toString().replaceFirst('Exception: ', '')));
    }
  }

  /// A catalogue title: the record and the source, side by side.
  ///
  /// AniList's page is AniList's — the words, the poster, the score, the
  /// cast — and the source found for it is only where the episodes come from.
  /// The two are fetched together rather than in turn, because neither needs
  /// the other to start, and the page should not wait twice.
  ///
  /// With no source the page still shows, with a "find a source" in place of
  /// Play: a title you cannot play yet is still a title you can read about,
  /// save, and track.
  ///
  /// TMDB titles keep the source's own page for now: every TMDB-backed
  /// provider here already renders TMDB's record, so the catalogue's would
  /// say the same things.
  Future<void> _loadFromCatalogue(
    Catalogue catalogue,
    DetailLoad event,
    CatalogueResolver resolver,
    Emitter<DetailState> emit,
  ) async {
    final linkFuture = resolver.resolve(
      catalogueId: catalogue.id,
      contentUrl: event.contentUrl,
      hint: event.hint,
    );

    if (catalogue == Catalogue.anilist && anilist != null) {
      final id = anilistIdFrom(
        event.contentUrl,
        externalId: event.hint?.externalId,
      );
      final recordFuture = id == null
          ? Future<dynamic>.value(null)
          : anilist!.mediaDetail(id).catchError((Object _) => null);
      final results = await Future.wait<dynamic>([linkFuture, recordFuture]);
      final via = results[0] as CatalogueLink?;
      final record = results[1];
      if (record != null) {
        emit(DetailLoaded(detailFromAnilist(record, via: via), via: via));
        return;
      }
      // AniList did not answer; fall through to the source's page, if there
      // is a source.
      await _loadFromSource(event, resolver, via, emit);
      return;
    }

    await _loadFromSource(event, resolver, await linkFuture, emit);
  }

  Future<void> _loadFromSource(
    DetailLoad event,
    CatalogueResolver resolver,
    CatalogueLink? via,
    Emitter<DetailState> emit,
  ) async {
    if (via == null) {
      emit(const DetailError('catalogue.no_source'));
      return;
    }
    final result = await useCase(via.contentUrl, provider: via.providerId);
    switch (result) {
      case Success(:final value):
        emit(DetailLoaded(value, via: via));
      case Failure(:final error):
        // A remembered link that no longer loads should not be tried again
        // next time: the source may have moved the title or dropped it.
        await resolver.forget(event.provider!, event.contentUrl);
        emit(DetailError(error.toString().replaceFirst('Exception: ', '')));
    }
  }
}
