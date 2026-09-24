import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/anilist/data/anilist_api.dart';
import 'package:soplay/features/detail/domain/entities/detail_entity.dart';
import 'package:soplay/features/detail/domain/services/catalogue_detail.dart';
import 'package:soplay/features/detail/domain/services/catalogue_resolver.dart';
import 'package:soplay/features/detail/domain/usecases/get_detail_usecase.dart';
import 'package:soplay/features/download/domain/repositories/offline_title_repository.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';

part 'detail_event.dart';
part 'detail_state.dart';

class DetailBloc extends Bloc<DetailEvent, DetailState> {
  final GetDetailUseCase useCase;

  /// Null only in tests that never open a catalogue title.
  final CatalogueResolver? resolver;
  final AnilistApi? anilist;

  /// Fetches TMDB's record for a catalogue url. Null in tests.
  final Future<Map<String, dynamic>> Function(String contentUrl)? tmdbDetail;

  /// The saved copy of a downloaded title. Null in tests that never go
  /// offline.
  final OfflineTitleRepository? offline;

  /// True when the device has no network at all, so a title with a saved copy
  /// opens from it without waiting for a request that cannot succeed.
  final Future<bool> Function()? isOffline;

  DetailBloc({
    required this.useCase,
    this.resolver,
    this.anilist,
    this.tmdbDetail,
    this.offline,
    this.isOffline,
  }) : super(const DetailInitial()) {
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

    final saved = offline?.get(event.contentUrl);
    if (saved != null && await (isOffline?.call() ?? Future.value(false))) {
      emit(DetailLoaded(saved.toDetail(), offline: true));
      return;
    }

    final result = await useCase(event.contentUrl, provider: event.provider);
    switch (result) {
      case Success(:final value):
        emit(DetailLoaded(value));
        await offline?.noteDetail(value);
      case Failure(:final error):
        if (saved != null) {
          emit(DetailLoaded(saved.toDetail(), offline: true));
          return;
        }
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
  Future<void> _loadFromCatalogue(
    Catalogue catalogue,
    DetailLoad event,
    CatalogueResolver resolver,
    Emitter<DetailState> emit,
  ) async {
    // `locate` rather than `resolve`: the two answer the same question, but
    // this one also says why it found nothing. Every miss used to arrive as the
    // same sentence — "None of your sources has this title" — including the two
    // that are not about the title at all: having no reader installed for a
    // manga, and having every source time out. Telling somebody to add a source
    // that carries it, when the truth is that nothing answered, sends them to
    // install a source they already have.
    final resolution = resolver.locate(
      catalogueId: catalogue.id,
      contentUrl: event.contentUrl,
      hint: event.hint,
    );

    // All three AniList shelves: the anime one and the two readers. Only the
    // anime shelf was matched here, so a manga or a light novel fell through
    // to "no source" with its record never asked for.
    if (catalogue.isAnilist && anilist != null) {
      final id = anilistIdFrom(
        event.contentUrl,
        externalId: event.hint?.externalId,
      );
      final type = catalogue.mode == ContentMode.video ? 'ANIME' : 'MANGA';
      final record = id == null
          ? null
          : await anilist!
                .mediaDetail(id, type: type)
                .catchError((Object _) => null);
      if (record != null) {
        // The record alone, straight away. The page used to wait for BOTH this
        // and the source search, so every catalogue title cost the slower of
        // the two — which was always the search, and which is the one thing on
        // the page nothing else depends on. Everything AniList knows is already
        // here: the poster, the words, the score, the cast.
        emit(
          DetailLoaded(
            detailFromAnilist(record, via: null),
            via: null,
            resolving: true,
          ),
        );
        final found = await resolution;
        emit(
          DetailLoaded(
            detailFromAnilist(record, via: found.link),
            via: found.link,
          ),
        );
        return;
      }
      // AniList did not answer; fall through to the source's page, if there
      // is a source.
      await _loadFromSource(event, resolver, await resolution, emit);
      return;
    }

    if (catalogue == Catalogue.tmdb && tmdbDetail != null) {
      final record = await tmdbDetail!(
        event.contentUrl,
      ).then<Map<String, dynamic>?>((m) => m).catchError((Object _) => null);
      if (record is Map<String, dynamic>) {
        emit(
          DetailLoaded(
            detailFromTmdb(record, via: null),
            via: null,
            resolving: true,
          ),
        );
        final found = await resolution;
        emit(
          DetailLoaded(
            detailFromTmdb(record, via: found.link),
            via: found.link,
          ),
        );
        return;
      }
      await _loadFromSource(event, resolver, await resolution, emit);
      return;
    }

    await _loadFromSource(event, resolver, await resolution, emit);
  }

  /// What to say when no source was found, which depends entirely on why.
  static String _missMessage(CatalogueMiss? miss) => switch (miss) {
    CatalogueMiss.noSourcesOfKind => 'catalogue.miss_no_sources_of_kind',
    CatalogueMiss.sourcesUnreachable => 'catalogue.miss_unreachable',
    CatalogueMiss.nothingToSearch => 'catalogue.miss_nothing_to_search',
    // The only one the old single message actually described.
    _ => 'catalogue.no_source',
  };

  Future<void> _loadFromSource(
    DetailLoad event,
    CatalogueResolver resolver,
    CatalogueResolution found,
    Emitter<DetailState> emit,
  ) async {
    final via = found.link;
    if (via == null) {
      emit(DetailError(_missMessage(found.miss)));
      return;
    }
    final result = await useCase(via.contentUrl, provider: via.providerId);
    switch (result) {
      case Success(:final value):
        emit(DetailLoaded(value, via: via));
        await offline?.noteDetail(value);
      case Failure(:final error):
        final saved = offline?.get(via.contentUrl);
        if (saved != null) {
          emit(DetailLoaded(saved.toDetail(), via: via, offline: true));
          return;
        }
        // A remembered link that no longer loads should not be tried again
        // next time: the source may have moved the title or dropped it.
        await resolver.forget(event.provider!, event.contentUrl);
        emit(DetailError(error.toString().replaceFirst('Exception: ', '')));
    }
  }
}
