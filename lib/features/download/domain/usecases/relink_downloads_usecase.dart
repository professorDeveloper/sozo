import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/download/domain/entities/offline_title.dart';
import 'package:soplay/features/download/domain/offline_relink.dart';
import 'package:soplay/features/download/domain/repositories/download_repository.dart';
import 'package:soplay/features/download/domain/repositories/offline_title_repository.dart';

/// Carries watch and read progress from the old source's keys to the new.
typedef ProgressMigration = Future<void> Function(RelinkPlan plan);

class RelinkOutcome {
  const RelinkOutcome({required this.moved, required this.left});

  final int moved;

  /// Downloads that stayed with the old source.
  final int left;
}

/// Points a downloaded title at another source without re-downloading it.
class RelinkDownloadsUseCase {
  const RelinkDownloadsUseCase({
    required DownloadRepository downloads,
    required OfflineTitleRepository titles,
    ProgressMigration? migrateProgress,
  }) : _downloads = downloads,
       _titles = titles,
       _migrateProgress = migrateProgress;

  final DownloadRepository _downloads;
  final OfflineTitleRepository _titles;
  final ProgressMigration? _migrateProgress;

  RelinkPlan plan(
    String groupKey, {
    required String provider,
    required String contentUrl,
    required List<EpisodeEntity> episodes,
  }) => OfflineRelink.plan(
    items: [
      for (final d in _downloads.items())
        if (d.groupKey == groupKey) d,
    ],
    provider: provider,
    contentUrl: contentUrl,
    episodes: episodes,
    taken: (id) => _downloads.byId(id) != null,
  );

  Future<RelinkOutcome> call(
    RelinkPlan plan, {
    String? providerName,
    List<EpisodeEntity> episodes = const [],
  }) async {
    final moved = await _downloads.relink(plan.moves);
    if (moved > 0) {
      final old =
          _titles.get(plan.fromContentUrl) ??
          OfflineTitle.fromItems([for (final m in plan.moves) m.from]);
      final list = episodes.length > OfflineTitle.maxEpisodes
          ? episodes.sublist(0, OfflineTitle.maxEpisodes)
          : episodes;
      await _titles.save(
        old.relinked(
          contentUrl: plan.contentUrl,
          provider: plan.provider,
          providerName: providerName,
          episodes: list.isEmpty ? null : list,
        ),
      );
      await _migrateProgress?.call(plan);
      final stillThere = _downloads.items().any(
        (d) => d.groupKey == plan.fromContentUrl,
      );
      if (!stillThere) await _titles.remove(plan.fromContentUrl);
    }
    return RelinkOutcome(moved: moved, left: plan.total - moved);
  }
}
