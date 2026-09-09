import 'package:equatable/equatable.dart';

import 'package:soplay/features/download/domain/entities/download_location.dart';
import 'package:soplay/features/download/presentation/bloc/downloads_state.dart';

sealed class DownloadsEvent extends Equatable {
  const DownloadsEvent();

  @override
  List<Object?> get props => const [];
}

/// Subscribe, verify what is on disk, and draw.
class DownloadsStarted extends DownloadsEvent {
  const DownloadsStarted();
}

/// The library changed under us — the repository ticked.
class DownloadsRefreshed extends DownloadsEvent {
  const DownloadsRefreshed();
}

class DownloadsFilterChanged extends DownloadsEvent {
  const DownloadsFilterChanged(this.filter);
  final DownloadsFilter filter;
  @override
  List<Object?> get props => [filter];
}

class DownloadsSortChanged extends DownloadsEvent {
  const DownloadsSortChanged(this.sort);
  final DownloadsSort sort;
  @override
  List<Object?> get props => [sort];
}

class DownloadsPauseRequested extends DownloadsEvent {
  const DownloadsPauseRequested(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

class DownloadsResumeRequested extends DownloadsEvent {
  const DownloadsResumeRequested(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

/// Start again after a failure, or fetch a missing file back.
class DownloadsRetryRequested extends DownloadsEvent {
  const DownloadsRetryRequested(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

/// Every failed or missing row at once.
class DownloadsRetryAllRequested extends DownloadsEvent {
  const DownloadsRetryAllRequested();
}

class DownloadsRemoveRequested extends DownloadsEvent {
  const DownloadsRemoveRequested(this.ids);
  final List<String> ids;
  @override
  List<Object?> get props => [ids];
}

class DownloadsClearRequested extends DownloadsEvent {
  const DownloadsClearRequested();
}

/// Delete folders no row points at.
class DownloadsSweepRequested extends DownloadsEvent {
  const DownloadsSweepRequested();
}

/// Move the whole library to another volume.
class DownloadsLocationChosen extends DownloadsEvent {
  const DownloadsLocationChosen(this.location);
  final DownloadLocation location;
  @override
  List<Object?> get props => [location.path];
}

class DownloadsWifiOnlyToggled extends DownloadsEvent {
  const DownloadsWifiOnlyToggled(this.value);
  final bool value;
  @override
  List<Object?> get props => [value];
}
