import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/torrent/torrent_status.dart';
import 'package:soplay/features/torrent/data/indexers/nyaa_indexer.dart';
import 'package:soplay/features/torrent/data/info_hash.dart';
import 'package:soplay/features/torrent/data/torrent_search_repository.dart';
import 'package:soplay/features/torrent/data/torrent_trackers.dart';
import 'package:soplay/features/torrent/domain/entities/release_info.dart';
import 'package:soplay/features/torrent/domain/entities/torrent_result.dart';
import 'package:soplay/features/torrent/presentation/widgets/torrent_file_picker_sheet.dart';

TorrentFileEntry _file(String path, int bytes, {int id = 1}) =>
    TorrentFileEntry(id: id, path: path, lengthBytes: bytes);

const _gb = 1024 * 1024 * 1024;

void main() {
  group('InfoHash', () {
    test('passes hex through, lowercased', () {
      expect(
        InfoHash.normalize('7287EC428AD3C76C565297C54FC8C9D2A397C63F'),
        '7287ec428ad3c76c565297c54fc8c9d2a397c63f',
      );
    });

    test('decodes the Base32 form Tokyo Toshokan magnets use', () {
      // Same torrent, both encodings — this equivalence is what makes
      // cross-tracker deduplication work at all.
      expect(
        InfoHash.normalize('JASFEDYP3ZEKOH2OWSYV54LT7OPI2NDQ'),
        InfoHash.normalize('4824520f0fde48a71f4eb4b15ef173fb9e8d3470'),
      );
    });

    test('pulls the hash out of a magnet', () {
      expect(
        InfoHash.fromMagnet('magnet:?xt=urn:btih:JASFEDYP3ZEKOH2OWSYV54LT7OPI2NDQ&tr=x'),
        '4824520f0fde48a71f4eb4b15ef173fb9e8d3470',
      );
    });

    test('rejects anything that is not a v1 info hash', () {
      for (final junk in ['', 'abc', 'zzzz', '12345', null]) {
        expect(InfoHash.normalize(junk), isNull, reason: 'for $junk');
      }
    });
  });

  group('size parsing', () {
    test('reads binary and decimal units apart', () {
      // Nyaa reports GiB, others report GB; treating them alike is a 7% lie.
      expect(NyaaIndexer.parseSize('1 GiB'), 1073741824);
      expect(NyaaIndexer.parseSize('1 GB'), 1000000000);
      expect(NyaaIndexer.parseSize('1.4 GiB'), 1503238554);
      expect(NyaaIndexer.parseSize('805 MB'), 805000000);
    });

    test('returns null rather than guessing', () {
      expect(NyaaIndexer.parseSize('unknown'), isNull);
      expect(NyaaIndexer.parseSize(null), isNull);
    });
  });

  group('TorrentResult.engineLink', () {
    test('builds a magnet from a bare info hash and attaches trackers', () {
      const result = TorrentResult(
        title: '[SubsPlease] Show - 01 (1080p)',
        indexerId: 'nyaa',
        indexerName: 'Nyaa',
        release: ReleaseInfo(),
        infoHash: '7287ec428ad3c76c565297c54fc8c9d2a397c63f',
      );

      final link = result.engineLink(
        extraTrackers: TorrentTrackers.forIndexer('nyaa'),
      )!;

      expect(link, startsWith('magnet:?xt=urn:btih:7287ec42'));
      expect(link, contains('dn='));
      // Without trackers a magnet leans on DHT alone, which is slow on mobile
      // and disabled for private torrents.
      expect(link, contains('tr='));
      expect(
        Uri.parse(link).queryParametersAll['tr']!.length,
        TorrentTrackers.forIndexer('nyaa').length,
      );
    });

    test('does not duplicate a tracker the magnet already carries', () {
      const tracker = 'udp://tracker.opentrackr.org:1337/announce';
      const result = TorrentResult(
        title: 'x',
        indexerId: 'tokyotosho',
        indexerName: 'Tokyo Toshokan',
        release: ReleaseInfo(),
        magnetUrl: 'magnet:?xt=urn:btih:abc&tr=$tracker',
      );

      final link = result.engineLink(extraTrackers: const [tracker])!;
      expect(tracker.allMatches(link).length, 1);
    });

    test('falls back to the .torrent URL when there is no hash', () {
      const result = TorrentResult(
        title: 'x',
        indexerId: 'shana',
        indexerName: 'Shana',
        release: ReleaseInfo(),
        torrentFileUrl: 'https://example.org/1.torrent',
      );
      expect(result.engineLink(), 'https://example.org/1.torrent');
    });
  });

  group('SwarmHealth', () {
    test('an unreported seeder count is unknown, not dead', () {
      // Tokyo Toshokan publishes no swarm data. Reading that as zero would
      // grey out every row it returns.
      expect(SwarmHealth.fromSeeders(null), SwarmHealth.unknown);
      expect(SwarmHealth.fromSeeders(null).isStreamable, isTrue);
      expect(SwarmHealth.fromSeeders(0), SwarmHealth.dead);
      expect(SwarmHealth.fromSeeders(0).isStreamable, isFalse);
    });
  });

  group('TorrentFilters', () {
    TorrentResult withRelease(ReleaseInfo release, {int? seeders = 10}) =>
        TorrentResult(
          title: 'x',
          indexerId: 'nyaa',
          indexerName: 'Nyaa',
          release: release,
          seeders: seeders,
        );

    test('keeps releases whose resolution could not be parsed', () {
      // An unparseable name is not evidence of a bad release; dropping it
      // would hide good torrents for a parser gap.
      const filters = TorrentFilters(minResolution: 1080);
      expect(filters.allows(withRelease(const ReleaseInfo())), isTrue);
      expect(
        filters.allows(withRelease(const ReleaseInfo(resolutionHeight: 720))),
        isFalse,
      );
    });

    test('never filters an unknown seeder count by minSeeders', () {
      const filters = TorrentFilters(minSeeders: 5);
      expect(filters.allows(withRelease(const ReleaseInfo(), seeders: null)),
          isTrue);
      expect(
          filters.allows(withRelease(const ReleaseInfo(), seeders: 2)), isFalse);
    });

    test('drops mini-encodes by default', () {
      const filters = TorrentFilters();
      expect(
        filters.allows(
            withRelease(const ReleaseInfo(source: ReleaseSource.miniEncode))),
        isFalse,
      );
    });
  });

  group('TorrentStatus file selection', () {
    test('prefers the biggest real video and skips samples and extras', () {
      final status = TorrentStatus(
        hash: 'h',
        state: TorrentState.working,
        label: 'working',
        files: [
          _file('Sample/sample.mkv', 8 * 1024 * 1024, id: 1),
          _file('Show - 01.mkv', 2 * _gb, id: 2),
          _file('Show - 01.ass', 40 * 1024, id: 3),
          _file('Extras/creditless OP.mkv', 60 * 1024 * 1024, id: 4),
        ],
      );

      expect(status.videoFiles.first.name, 'Show - 01.mkv');
      expect(status.subtitleFiles.single.name, 'Show - 01.ass');
      // The creditless OP is a real video, so it stays offerable — just not
      // first.
      expect(status.videoFiles.length, 2);
    });

    test('asks the user only when there really are several videos', () {
      TorrentStatus withFiles(List<TorrentFileEntry> files) => TorrentStatus(
            hash: 'h',
            state: TorrentState.working,
            label: '',
            files: files,
          );

      expect(
        withFiles([_file('Show - 01.mkv', _gb)]).needsFileChoice,
        isFalse,
      );
      expect(
        withFiles([
          _file('Show - 01.mkv', _gb, id: 1),
          _file('Show - 02.mkv', _gb, id: 2),
        ]).needsFileChoice,
        isTrue,
      );
    });

    test('has no metadata until the swarm answers', () {
      // What `add` returns for a magnet: registered, no file list yet. Building
      // a stream URL from this is the bug the preparation flow exists to avoid.
      const status = TorrentStatus(
        hash: 'h',
        state: TorrentState.gettingInfo,
        label: 'Getting info',
      );
      expect(status.hasMetadata, isFalse);
      expect(status.state.isTransient, isTrue);
    });

    test('reports pre-buffer progress, not overall download', () {
      const status = TorrentStatus(
        hash: 'h',
        state: TorrentState.preloading,
        label: '',
        preloadedBytes: 5,
        preloadTargetBytes: 20,
        totalBytes: 100000,
      );
      expect(status.preloadProgress, 0.25);
    });
  });

  _relevanceGuardTests();

  group('file picker ordering', () {
    test('sorts episode 2 before episode 10', () {
      final names = [
        'Show - 10.mkv',
        'Show - 2.mkv',
        'Show - 1.mkv',
        'Show - 20.mkv',
      ]..sort(TorrentFilePickerSheet.naturalCompare);

      expect(names, [
        'Show - 1.mkv',
        'Show - 2.mkv',
        'Show - 10.mkv',
        'Show - 20.mkv',
      ]);
    });

    test('handles inconsistent zero padding across one torrent', () {
      final names = ['ep09.mkv', 'ep10.mkv', 'ep1.mkv']
        ..sort(TorrentFilePickerSheet.naturalCompare);
      expect(names, ['ep1.mkv', 'ep09.mkv', 'ep10.mkv']);
    });
  });
}

/// Regression guard for the worst bug this feature has had.
///
/// Two of the three trackers were never searching at all. Both APIs ignore an
/// unrecognised parameter instead of rejecting it, so `q=` on nekoBT and
/// `search=` on Tokyo Toshokan silently returned each site's default listing —
/// a search for "frieren" and one for "zzzznonexistentzzz" came back
/// byte-identical. Nothing errored, nothing logged, and the screen filled with
/// confident-looking results for entirely different shows.
void _relevanceGuardTests() {
  TorrentResult row(String title) => TorrentResult(
        title: title,
        indexerId: 'x',
        indexerName: 'X',
        release: const ReleaseInfo(),
      );

  group('query tokenisation', () {
    test('drops words that never appear in a release name', () {
      // Nobody names a file "season" or "episode"; releases use S02E05.
      expect(
        TorrentSearchRepository.significantTokens('Wednesday season 2 episode 6'),
        {'wednesday'},
      );
    });

    test('is empty for a query with no ASCII words, disabling the guard', () {
      // A Japanese or Cyrillic title must not be filtered by a check that
      // cannot read it.
      expect(TorrentSearchRepository.significantTokens('葬送のフリーレン'), isEmpty);
    });
  });

  group('ignoredTheQuery', () {
    final tokens = TorrentSearchRepository.significantTokens('frieren');

    test('catches a tracker that returned its front page', () {
      expect(
        TorrentSearchRepository.ignoredTheQuery([
          row('[Arg0] Elf 17 (1987) (BD 1080p x265 Opus 2.0)'),
          row('[Knight-Subs] Bleach Thousand-Year Blood War - E45v2'),
          row('[sam] Grand Blue Dreaming - S03E07'),
        ], tokens),
        isTrue,
      );
    });

    test('keeps a batch where the title uses a different official name', () {
      // The whole reason this is a batch check and not a per-row filter: a
      // romaji title and an English one are the same show, and per-row matching
      // would throw away exactly these.
      expect(
        TorrentSearchRepository.ignoredTheQuery([
          row('[Ironclad] Sousou no Frieren - S02 [BD.1080p.AV1]'),
          row('[Arg0] Elf 17 (1987)'),
        ], tokens),
        isFalse,
      );
    });

    test('never fires on an honestly empty result', () {
      // Nyaa really does have no "Wednesday" anime. That is a valid answer, not
      // a broken tracker, and reporting it as a failure sent users looking for
      // a problem that was not there.
      expect(TorrentSearchRepository.ignoredTheQuery(const [], tokens), isFalse);
    });

    test('never fires when the query has no usable tokens', () {
      expect(
        TorrentSearchRepository.ignoredTheQuery([row('anything at all')], {}),
        isFalse,
      );
    });
  });
}
