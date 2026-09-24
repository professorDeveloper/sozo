import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/entities/detail_entity.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/entities/playback_entity.dart';
import 'package:soplay/features/download/data/models/offline_title_model.dart';
import 'package:soplay/features/download/domain/entities/download_status.dart';
import 'package:soplay/features/download/domain/entities/downloaded_title.dart';
import 'package:soplay/features/download/domain/entities/offline_title.dart';

import 'offline_fakes.dart';

DetailEntity _detail() => const DetailEntity(
  provider: 'old',
  contentId: '1',
  contentUrl: 'https://old.test/show',
  title: 'Show',
  description: 'A show about things.',
  thumbnail: 'https://img.test/p.jpg',
  year: 2020,
  duration: null,
  country: 'JP',
  director: null,
  genres: ['Drama', 'Comedy'],
  cast: [],
  likes: 5,
  dislikes: 0,
  isSerial: true,
  isFavorited: true,
  screenshots: [],
  related: [],
);

PlaybackEntity _playback(
  List<int> numbers, {
  int page = 1,
  int totalPages = 1,
}) => PlaybackEntity(
  provider: 'old',
  contentUrl: 'https://old.test/show',
  isSerial: true,
  episodes: [
    for (final n in numbers)
      EpisodeEntity(episode: n, label: 'Episode $n', mediaRef: 'ref$n'),
  ],
  videoSources: const [],
  playerSrc: null,
  headers: const {'Referer': 'https://old.test/'},
  page: page,
  totalPages: totalPages,
);

void main() {
  group('a snapshot', () {
    test('survives the round trip through storage', () {
      final title = const OfflineTitle(
        contentUrl: 'https://old.test/show',
        provider: 'old',
        title: 'Show',
        savedAt: 1,
      ).withDetail(_detail(), now: 2).withPlayback(_playback([1, 2]), now: 3);

      final back = OfflineTitleModel.fromJson(
        jsonDecode(jsonEncode(OfflineTitleModel.toJson(title)))
            as Map<String, dynamic>,
      )!;

      expect(back.title, 'Show');
      expect(back.description, 'A show about things.');
      expect(back.genres, ['Drama', 'Comedy']);
      expect(back.year, 2020);
      expect(back.isSerial, isTrue);
      expect(back.headers, {'Referer': 'https://old.test/'});
      expect(back.savedAt, 3);
      expect([for (final e in back.episodes) e.mediaRef], ['ref1', 'ref2']);
    });

    test('an unreadable row is dropped, not thrown', () {
      expect(OfflineTitleModel.fromJson({'title': 'no url'}), isNull);
    });

    test('opens as a detail page and a one-page list', () {
      final title = const OfflineTitle(
        contentUrl: 'https://old.test/show',
        provider: 'old',
        title: 'Show',
        savedAt: 0,
      ).withPlayback(_playback(List.generate(250, (i) => i + 1)));

      final detail = title.toDetail();
      expect(detail.contentUrl, 'https://old.test/show');
      expect(detail.provider, 'old');

      final playback = title.toPlayback();
      expect(playback.episodes, hasLength(250));
      // One page holding everything: nothing on the list may page the source.
      expect(playback.totalPages, 1);
      expect(playback.size, 250);
      expect(playback.total, 250);
    });

    test('a later page of a long run adds to the saved list', () {
      final title =
          const OfflineTitle(
                contentUrl: 'https://old.test/show',
                provider: 'old',
                title: 'Show',
                savedAt: 0,
              )
              .withPlayback(_playback([1, 2], totalPages: 2))
              .withPlayback(_playback([3, 4], page: 2, totalPages: 2));
      expect([for (final e in title.episodes) e.episode], [1, 2, 3, 4]);
    });

    test('is built from the rows alone when nothing else is known', () {
      final title = OfflineTitle.fromItems([episode(3), episode(1)], now: 9);
      expect(title.title, 'Show');
      expect(title.isSerial, isTrue);
      expect([for (final e in title.episodes) e.episode], [1, 3]);

      final film = OfflineTitle.fromItems([movie()]);
      expect(film.isSerial, isFalse);
      expect(film.episodes, isEmpty);
    });
  });

  group('the downloaded library', () {
    test('one card per title, only titles with something finished', () {
      final titles = DownloadedTitle.group([
        episode(1),
        episode(2),
        episode(3, status: DownloadStatus.downloading),
        chapter(1, status: DownloadStatus.failed),
        movie(),
      ]);

      expect(titles, hasLength(2));
      final show = titles.firstWhere((t) => t.key == 'https://old.test/show');
      expect(show.completed, 2);
      expect(show.total, 3);
      expect(show.sizeBytes, 200);
      expect(show.isMovie, isFalse);
      expect(titles.firstWhere((t) => t.key.endsWith('/film')).isMovie, isTrue);
    });

    test('the saved title name wins over the row', () {
      final titles = DownloadedTitle.group(
        [episode(1)],
        snapshotOf: (_) => const OfflineTitle(
          contentUrl: 'https://old.test/show',
          provider: 'old',
          title: 'The Show (2020)',
          savedAt: 0,
          thumbnail: 'https://img.test/saved.jpg',
        ),
      );
      expect(titles.single.title, 'The Show (2020)');
      expect(titles.single.thumbnailUrl, 'https://img.test/saved.jpg');
    });

    test('most recently finished first', () {
      final titles = DownloadedTitle.group([
        episode(1),
        episode(9, contentUrl: 'https://old.test/newer'),
      ]);
      expect(titles.first.key, 'https://old.test/newer');
    });
  });
}
