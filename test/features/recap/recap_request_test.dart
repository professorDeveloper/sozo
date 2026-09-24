import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';
import 'package:soplay/features/recap/domain/recap.dart';

HistoryItem _item({
  bool isSerial = true,
  int? episodeNumber,
  int? episodeIndex,
  int positionMs = 300000,
  int durationMs = 1400000,
  String? mediaType,
  String? label,
}) => HistoryItem(
  contentUrl: 'https://example.com/show',
  provider: 'asilmedia',
  title: 'Show',
  isSerial: isSerial,
  episodeNumber: episodeNumber,
  episodeIndex: episodeIndex,
  episodeLabel: label,
  positionMs: positionMs,
  durationMs: durationMs,
  watchedAt: 1,
  mediaType: mediaType,
);

void main() {
  group('RecapRequest.fromHistory', () {
    test('mid-episode: recaps everything before the episode in progress', () {
      final r = RecapRequest.fromHistory(
        _item(episodeNumber: 5, label: '2-fasl 5-qism'),
        tmdbId: 1399,
      )!;
      expect(r.episode, 5);
      expect(r.fallbackEpisode, isNull);
      expect(r.label, '2-fasl 5-qism');
      expect(r.tmdbId, 1399);
      expect(r.provider, 'asilmedia');
    });

    test('a finished episode points at the next, falling back to itself', () {
      final r = RecapRequest.fromHistory(
        _item(episodeNumber: 5, positionMs: 1390000),
      )!;
      expect(r.episode, 6);
      expect(r.fallbackEpisode, 5);
    });

    test('episode index is used when the number is missing', () {
      final r = RecapRequest.fromHistory(_item(episodeIndex: 3))!;
      expect(r.episode, 4);
    });

    test('nothing before episode 1 to recap', () {
      expect(RecapRequest.fromHistory(_item(episodeNumber: 1)), isNull);
    });

    test('finishing episode 1 recaps it, with no fallback to episode 1', () {
      final r = RecapRequest.fromHistory(
        _item(episodeNumber: 1, positionMs: 1400000),
      )!;
      expect(r.episode, 2);
      expect(r.fallbackEpisode, isNull);
    });

    test('films, reader rows and unnumbered rows have no recap', () {
      expect(
        RecapRequest.fromHistory(_item(isSerial: false, episodeNumber: 4)),
        isNull,
      );
      expect(
        RecapRequest.fromHistory(_item(episodeNumber: 4, mediaType: 'manga')),
        isNull,
      );
      expect(RecapRequest.fromHistory(_item()), isNull);
    });
  });

  group('Recap.fromJson', () {
    test('reads the server shape', () {
      final recap = Recap.fromJson({
        'title': 'Show',
        'tmdbId': 1399,
        'anilistId': null,
        'season': 2,
        'episode': 5,
        'upToEpisode': 4,
        'attribution': 'TMDB',
        'items': [
          {'season': 1, 'episode': null, 'name': 'Season 1', 'overview': 'A'},
          {'season': 2, 'episode': 4, 'name': 'Four', 'overview': 'B'},
          'junk',
        ],
        'generatedAt': '2026-09-24T00:00:00.000Z',
        'lang': 'en',
        'source': 'llm',
        'text': 'First.\n\nSecond.',
      }, requestedEpisode: 5)!;
      expect(recap.title, 'Show');
      expect(recap.season, 2);
      expect(recap.upToEpisode, 4);
      expect(recap.attribution, 'TMDB');
      expect(recap.fromModel, isTrue);
      expect(recap.paragraphs, ['First.', 'Second.']);
      expect(recap.items, hasLength(2));
      expect(recap.items.first.isSeason, isTrue);
      expect(recap.items.last.episode, 4);
    });

    test('a body without text is not a recap', () {
      expect(Recap.fromJson({'text': '  '}, requestedEpisode: 3), isNull);
      expect(Recap.fromJson('<html>', requestedEpisode: 3), isNull);
    });

    test('stitched text is not credited to the model', () {
      final recap = Recap.fromJson({
        'text': 'x',
        'source': 'stitched',
      }, requestedEpisode: 3)!;
      expect(recap.fromModel, isFalse);
      expect(recap.episode, 3);
    });
  });
}
