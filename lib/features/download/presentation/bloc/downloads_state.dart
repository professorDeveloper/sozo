import 'package:equatable/equatable.dart';

import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/download/domain/entities/download_location.dart';
import 'package:soplay/features/download/domain/entities/download_status.dart';
import 'package:soplay/features/download/domain/entities/storage_usage.dart';

/// Which rows the list is showing.
enum DownloadsFilter {
  all,
  active,
  completed,

  /// Failed and missing together: from the viewer's side they are one thing —
  /// "this is not watchable and I would like it to be".
  problems;

  bool matches(DownloadItem item) => switch (this) {
        DownloadsFilter.all => true,
        DownloadsFilter.active => item.status.isActive ||
            item.status == DownloadStatus.paused,
        DownloadsFilter.completed => item.status == DownloadStatus.completed,
        DownloadsFilter.problems => item.status == DownloadStatus.failed ||
            item.status == DownloadStatus.missing,
      };
}

/// How the list is ordered.
enum DownloadsSort { newest, title, size }

/// One title and everything downloaded from it.
///
/// A series used to fill the screen one episode per row: twenty rows of the
/// same poster and the same name, differing by a number, with "Clear all" as
/// the only way to get rid of them. Grouping makes a season one row that opens.
class DownloadGroup extends Equatable {
  const DownloadGroup({required this.key, required this.items});

  final String key;

  /// Episodes in ascending order, or the single item for a film.
  final List<DownloadItem> items;

  DownloadItem get lead => items.first;

  bool get isSingle => items.length == 1;

  String get title => lead.title;

  int get sizeBytes =>
      items.fold(0, (sum, item) => sum + item.sizeBytes);

  int get newestAt => items.fold(
        0,
        (newest, item) => item.createdAt > newest ? item.createdAt : newest,
      );

  int countWhere(bool Function(DownloadItem) test) =>
      items.where(test).length;

  bool get hasActive => items.any((i) => i.status.isActive);

  bool get hasProblem => items.any(
        (i) =>
            i.status == DownloadStatus.failed ||
            i.status == DownloadStatus.missing,
      );

  List<String> get ids => [for (final i in items) i.id];

  @override
  List<Object?> get props => [key, items.map((i) => i.id).toList()];
}

class DownloadsState extends Equatable {
  const DownloadsState({
    this.groups = const [],
    this.total = 0,
    this.filter = DownloadsFilter.all,
    this.sort = DownloadsSort.newest,
    this.usage = StorageUsage.empty,
    this.waitingForWifi = false,
    this.wifiOnly = false,
    this.loading = true,
    this.busy = false,
    this.locations = const [],
    this.locationPath = '',
  });

  /// What the list draws, already filtered, sorted and grouped.
  final List<DownloadGroup> groups;

  /// Rows in the library BEFORE filtering, so an empty filtered list can say
  /// "nothing matches this filter" rather than "no downloads yet".
  final int total;

  final DownloadsFilter filter;
  final DownloadsSort sort;
  final StorageUsage usage;
  final bool waitingForWifi;
  final bool wifiOnly;
  final bool loading;

  /// A long-running action — an export, an orphan sweep, a move — is in
  /// flight.
  final bool busy;

  /// Where the library can be kept. One entry means there is no choice, and
  /// the row is hidden rather than offering a list of one.
  final List<DownloadLocation> locations;

  /// The volume it is on now.
  final String locationPath;

  DownloadLocation? get currentLocation {
    for (final l in locations) {
      if (l.path == locationPath) return l;
    }
    return locations.isEmpty ? null : locations.first;
  }

  bool get canChooseLocation => locations.length > 1;

  bool get isEmpty => groups.isEmpty;

  DownloadsState copyWith({
    List<DownloadGroup>? groups,
    int? total,
    DownloadsFilter? filter,
    DownloadsSort? sort,
    StorageUsage? usage,
    bool? waitingForWifi,
    bool? wifiOnly,
    bool? loading,
    bool? busy,
    List<DownloadLocation>? locations,
    String? locationPath,
  }) =>
      DownloadsState(
        groups: groups ?? this.groups,
        total: total ?? this.total,
        filter: filter ?? this.filter,
        sort: sort ?? this.sort,
        usage: usage ?? this.usage,
        waitingForWifi: waitingForWifi ?? this.waitingForWifi,
        wifiOnly: wifiOnly ?? this.wifiOnly,
        loading: loading ?? this.loading,
        busy: busy ?? this.busy,
        locations: locations ?? this.locations,
        locationPath: locationPath ?? this.locationPath,
      );

  @override
  List<Object?> get props => [
        groups,
        total,
        filter,
        sort,
        usage,
        waitingForWifi,
        wifiOnly,
        loading,
        busy,
        locations.map((l) => l.path).toList(),
        locationPath,
      ];
}
