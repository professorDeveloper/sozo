import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/download/domain/entities/download_status.dart';
import 'package:soplay/features/download/domain/usecases/control_download_usecase.dart';
import 'package:soplay/features/download/domain/entities/download_location.dart';
import 'package:soplay/features/download/domain/usecases/download_location_usecase.dart';
import 'package:soplay/features/download/domain/usecases/download_storage_usecase.dart';
import 'package:soplay/features/download/domain/usecases/get_downloads_usecase.dart';
import 'package:soplay/features/download/domain/usecases/remove_download_usecase.dart';
import 'package:soplay/features/download/domain/usecases/verify_downloads_usecase.dart';
import 'package:soplay/features/download/presentation/bloc/downloads_event.dart';
import 'package:soplay/features/download/presentation/bloc/downloads_state.dart';

export 'package:soplay/features/download/presentation/bloc/downloads_event.dart';
export 'package:soplay/features/download/presentation/bloc/downloads_state.dart';

/// The Downloads screen's state.
///
/// Everything it touches is a use case. The page below it renders and taps;
/// the repository above it owns the queue and the disk. That split is what
/// lets the screen show a "missing" row at all — the verification that
/// produces one is a domain operation the screen merely asks for on open,
/// rather than a filesystem check each widget did for itself.
class DownloadsBloc extends Bloc<DownloadsEvent, DownloadsState> {
  DownloadsBloc({
    required GetDownloadsUseCase getDownloads,
    required ControlDownloadUseCase control,
    required RemoveDownloadUseCase remove,
    required VerifyDownloadsUseCase verify,
    required DownloadStorageUseCase storage,
    required DownloadLocationUseCase location,
    required HiveService hive,
  })  : _get = getDownloads,
        _control = control,
        _remove = remove,
        _verify = verify,
        _storage = storage,
        _location = location,
        _hive = hive,
        super(const DownloadsState()) {
    on<DownloadsStarted>(_onStarted);
    on<DownloadsRefreshed>(_onRefreshed);
    on<DownloadsFilterChanged>(_onFilter);
    on<DownloadsSortChanged>(_onSort);
    on<DownloadsPauseRequested>(_onPause);
    on<DownloadsResumeRequested>(_onResume);
    on<DownloadsRetryRequested>(_onRetry);
    on<DownloadsRetryAllRequested>(_onRetryAll);
    on<DownloadsRemoveRequested>(_onRemove);
    on<DownloadsClearRequested>(_onClear);
    on<DownloadsSweepRequested>(_onSweep);
    on<DownloadsWifiOnlyToggled>(_onWifiOnly);
    on<DownloadsLocationChosen>(_onLocation);
  }

  final GetDownloadsUseCase _get;
  final ControlDownloadUseCase _control;
  final RemoveDownloadUseCase _remove;
  final VerifyDownloadsUseCase _verify;
  final DownloadStorageUseCase _storage;
  final DownloadLocationUseCase _location;
  final HiveService _hive;

  VoidCallback? _unsubscribe;

  Future<void> _onStarted(
    DownloadsStarted event,
    Emitter<DownloadsState> emit,
  ) async {
    void listener() {
      if (isClosed) return;
      add(const DownloadsRefreshed());
    }

    _get.revision.addListener(listener);
    _unsubscribe = () => _get.revision.removeListener(listener);

    emit(state.copyWith(wifiOnly: _hive.downloadWifiOnly));
    // Draw what is known first, then correct it. The sweep walks the whole
    // folder, and an empty screen while it runs is worse than a screen that
    // adjusts a moment later.
    _emitList(emit, loading: false);
    await _verify();
    if (isClosed) return;
    _emitList(emit, loading: false);
    await _refreshUsage(emit);
    await _refreshLocations(emit);
  }

  void _onRefreshed(DownloadsRefreshed event, Emitter<DownloadsState> emit) {
    _emitList(emit, loading: false);
  }

  void _onFilter(DownloadsFilterChanged event, Emitter<DownloadsState> emit) {
    emit(state.copyWith(filter: event.filter));
    _emitList(emit, loading: false);
  }

  void _onSort(DownloadsSortChanged event, Emitter<DownloadsState> emit) {
    emit(state.copyWith(sort: event.sort));
    _emitList(emit, loading: false);
  }

  Future<void> _onPause(
    DownloadsPauseRequested event,
    Emitter<DownloadsState> emit,
  ) =>
      _control.pause(event.id);

  Future<void> _onResume(
    DownloadsResumeRequested event,
    Emitter<DownloadsState> emit,
  ) =>
      _control.resume(event.id);

  Future<void> _onRetry(
    DownloadsRetryRequested event,
    Emitter<DownloadsState> emit,
  ) =>
      _control.retry(event.id);

  Future<void> _onRetryAll(
    DownloadsRetryAllRequested event,
    Emitter<DownloadsState> emit,
  ) async {
    for (final item in _get()) {
      if (item.status == DownloadStatus.failed ||
          item.status == DownloadStatus.missing) {
        await _control.retry(item.id);
      }
    }
  }

  Future<void> _onRemove(
    DownloadsRemoveRequested event,
    Emitter<DownloadsState> emit,
  ) async {
    await _remove.many(event.ids);
    if (isClosed) return;
    await _refreshUsage(emit);
  }

  Future<void> _onClear(
    DownloadsClearRequested event,
    Emitter<DownloadsState> emit,
  ) async {
    await _remove.all();
    if (isClosed) return;
    await _refreshUsage(emit);
  }

  Future<void> _onSweep(
    DownloadsSweepRequested event,
    Emitter<DownloadsState> emit,
  ) async {
    emit(state.copyWith(busy: true));
    await _storage.sweepOrphans();
    if (isClosed) return;
    emit(state.copyWith(busy: false));
    await _refreshUsage(emit);
  }

  Future<void> _onWifiOnly(
    DownloadsWifiOnlyToggled event,
    Emitter<DownloadsState> emit,
  ) async {
    emit(state.copyWith(wifiOnly: event.value));
    await _hive.setDownloadWifiOnly(event.value);
  }

  /// Moves the library, reporting what happened.
  ///
  /// Marked busy for the whole copy: it is minutes on a large library, and a
  /// screen that looks idle while every file is being moved invites a second
  /// tap that would start the move again.
  Future<void> _onLocation(
    DownloadsLocationChosen event,
    Emitter<DownloadsState> emit,
  ) async {
    emit(state.copyWith(busy: true));
    final outcome = await _location.moveTo(event.location);
    if (isClosed) return;
    emit(state.copyWith(busy: false));
    lastMoveOutcome = outcome;
    await _refreshLocations(emit);
    if (isClosed) return;
    _emitList(emit, loading: false);
    await _refreshUsage(emit);
  }

  /// What the last move did, for the screen to report once.
  ///
  /// Not in the state: it is an event, not a condition, and putting it there
  /// would make every later rebuild re-announce a move that finished minutes
  /// ago.
  MoveLocationOutcome? lastMoveOutcome;

  Future<void> _refreshLocations(Emitter<DownloadsState> emit) async {
    final locations = await _location();
    if (isClosed) return;
    final current = _hive.getDownloadLocation();
    emit(state.copyWith(
      locations: locations,
      locationPath: current.isNotEmpty
          ? current
          : (locations.isEmpty ? '' : locations.first.path),
    ));
  }

  Future<void> _refreshUsage(Emitter<DownloadsState> emit) async {
    final usage = await _storage.usage();
    if (isClosed) return;
    emit(state.copyWith(usage: usage));
  }

  void _emitList(Emitter<DownloadsState> emit, {required bool loading}) {
    final all = _get();
    final filtered = [
      for (final item in all)
        if (state.filter.matches(item)) item,
    ];
    emit(state.copyWith(
      groups: _group(filtered, state.sort),
      total: all.length,
      loading: loading,
      waitingForWifi: _get.isWaitingForWifi,
    ));
  }

  /// One row per title, with a film staying one row.
  ///
  /// Grouping is by [DownloadItem.groupKey] — the content url — rather than by
  /// the display title: two different shows can share a name, and one show can
  /// be titled differently by two sources, and neither of those should merge
  /// or split a season.
  static List<DownloadGroup> _group(
    List<DownloadItem> items,
    DownloadsSort sort,
  ) {
    final buckets = <String, List<DownloadItem>>{};
    final order = <String>[];
    for (final item in items) {
      final key = item.groupKey;
      final bucket = buckets.putIfAbsent(key, () {
        order.add(key);
        return <DownloadItem>[];
      });
      bucket.add(item);
    }

    final groups = [
      for (final key in order)
        DownloadGroup(
          key: key,
          items: buckets[key]!
            // Ascending by episode inside a group: a season reads 1, 2, 3 even
            // though the list itself is newest-first.
            ..sort((a, b) {
              final byEpisode =
                  (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0);
              return byEpisode != 0
                  ? byEpisode
                  : a.createdAt.compareTo(b.createdAt);
            }),
        ),
    ];

    switch (sort) {
      case DownloadsSort.newest:
        groups.sort((a, b) => b.newestAt.compareTo(a.newestAt));
      case DownloadsSort.title:
        groups.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case DownloadsSort.size:
        groups.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    }
    return groups;
  }

  @override
  Future<void> close() {
    _unsubscribe?.call();
    return super.close();
  }
}
