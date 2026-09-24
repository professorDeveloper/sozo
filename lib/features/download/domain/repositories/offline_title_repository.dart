import 'package:flutter/foundation.dart';

import 'package:soplay/features/detail/domain/entities/detail_entity.dart';
import 'package:soplay/features/detail/domain/entities/playback_entity.dart';
import 'package:soplay/features/download/domain/entities/offline_title.dart';

/// Title snapshots for everything that has downloads.
abstract class OfflineTitleRepository {
  ValueListenable<int> get revision;

  OfflineTitle? get(String contentUrl);

  List<OfflineTitle> all();

  /// Seen online. Kept in memory for a title with no downloads yet, and
  /// written through for one that has them, so the saved copy stays current.
  Future<void> noteDetail(DetailEntity detail);

  Future<void> noteEpisodes(PlaybackEntity playback, {String? contentUrl});

  Future<void> save(OfflineTitle title);

  Future<void> remove(String contentUrl);
}
