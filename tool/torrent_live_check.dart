// Live smoke check for the torrent indexers.
//
// Unit tests cover the parsers with fixed input; this one talks to the real
// trackers, because the failure mode that actually matters here is a site
// changing its feed or its markup, which no offline test can catch.
//
//   dart run tool/torrent_live_check.dart "frieren"
import 'package:soplay/features/torrent/data/indexers/torrent_indexer.dart';
import 'package:soplay/features/torrent/data/torrent_search_repository.dart';
import 'package:soplay/features/torrent/data/torrent_trackers.dart';
import 'package:soplay/features/torrent/domain/entities/torrent_result.dart';

Future<void> main(List<String> args) async {
  final term = args.isEmpty ? 'frieren' : args.join(' ');
  final repo = TorrentSearchRepository();

  for (final indexer in repo.indexers) {
    if (indexer.isNsfw) continue;
    final stopwatch = Stopwatch()..start();
    final results = await indexer.search(
      TorrentQuery(term: term, category: TorrentCategory.animeEnglish),
    );
    stopwatch.stop();

    print('\n=== ${indexer.name} — ${results.length} results '
        'in ${stopwatch.elapsedMilliseconds}ms');
    for (final r in results.take(3)) {
      print('  ${r.title}');
      print('    seed=${r.seeders ?? "?"} leech=${r.leechers ?? "?"} '
          'size=${r.displaySize ?? "?"} trusted=${r.trusted} health=${r.health.name}');
      print('    badges: ${r.release.badges.join(" · ")}');
      print('    group=${r.release.group} ep=${r.release.episode}'
          '${r.release.episodeEnd != null ? "-${r.release.episodeEnd}" : ""} '
          'batch=${r.release.batch}');
      final link = r.engineLink(extraTrackers: TorrentTrackers.forIndexer(r.indexerId));
      print('    link: ${link?.substring(0, link.length.clamp(0, 90))}...');
    }
  }

  print('\n\n######## INCREMENTAL (what the UI actually sees) ########');
  final clock = Stopwatch()..start();
  var merged = <TorrentResult>[];
  await for (final update in repo.searchIncremental(
    TorrentQuery(term: term, category: TorrentCategory.animeEnglish),
    filters: const TorrentFilters(minSeeders: 1, minResolution: 1080),
  )) {
    merged = update.results;
    print('  t=${clock.elapsedMilliseconds.toString().padLeft(5)}ms  '
        'rows=${update.results.length.toString().padLeft(3)}  '
        'pending=${update.pending}');
  }
  clock.stop();
  print('\n${merged.length} rows after dedup and filtering\n');
  for (final r in merged.take(8)) {
    final seeds = (r.seeders?.toString() ?? '?').padLeft(4);
    print('$seeds  ${r.indexerName.padRight(15)} '
        '${(r.displaySize ?? "?").padLeft(9)}  ${r.title}');
  }

  final withHash = merged.where((r) => r.infoHash != null).length;
  print('\ninfo hash resolved for $withHash/${merged.length} rows '
      '(needed for cross-tracker dedup)');
  repo.dispose();
}
