import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/mal/data/mal_tracker.dart';
import 'package:soplay/features/mal/domain/entities/mal_entities.dart';

void main() {
  group('statusFor', () {
    // The rule that is easy to get backwards, and silent when wrong: MAL models
    // a rewatch as a FLAG on a completed entry, not as a status. Sending any
    // status at all knocks the entry out of `completed` and ends the rewatch —
    // rewriting a list the user curated, with nothing on screen to say so.
    test('a rewatch is left completely alone', () {
      expect(
        MalTracker.statusFor(
          current: MalStatus.completed,
          isRewatching: true,
          episode: 3,
          total: 12,
        ),
        isNull,
      );
    });

    test('a rewatch is left alone even on the final episode', () {
      expect(
        MalTracker.statusFor(
          current: MalStatus.completed,
          isRewatching: true,
          episode: 12,
          total: 12,
        ),
        isNull,
      );
    });

    test('the last episode completes the show', () {
      expect(
        MalTracker.statusFor(
          current: MalStatus.watching,
          isRewatching: false,
          episode: 12,
          total: 12,
        ),
        MalStatus.completed,
      );
    });

    test('an entry already being watched is not rewritten', () {
      expect(
        MalTracker.statusFor(
          current: MalStatus.watching,
          isRewatching: false,
          episode: 4,
          total: 12,
        ),
        isNull,
      );
    });

    test('a title not on the list yet is added as watching', () {
      expect(
        MalTracker.statusFor(
          current: null,
          isRewatching: false,
          episode: 1,
          total: 12,
        ),
        MalStatus.watching,
      );
    });

    // Picking a dropped show back up is watching it again, which is the one
    // case where overwriting an existing status is the right answer.
    test('resuming a dropped show moves it back to watching', () {
      expect(
        MalTracker.statusFor(
          current: MalStatus.dropped,
          isRewatching: false,
          episode: 5,
          total: 24,
        ),
        MalStatus.watching,
      );
    });

    // An airing show has no trustworthy total. Guessing "completed" from a
    // missing one would mark a running series finished at episode 1.
    test('an unknown total never completes anything', () {
      expect(
        MalTracker.statusFor(
          current: null,
          isRewatching: false,
          episode: 9,
          total: null,
        ),
        MalStatus.watching,
      );
      expect(
        MalTracker.statusFor(
          current: null,
          isRewatching: false,
          episode: 9,
          total: 0,
        ),
        MalStatus.watching,
      );
    });
  });

  group('MalEntryState.fromAnime', () {
    test('reads progress, status and the rewatch flag', () {
      final state = MalEntryState.fromAnime(const {
        'id': 1735,
        'num_episodes': 500,
        'my_list_status': {
          'num_episodes_watched': 120,
          'status': 'watching',
          'is_rewatching': true,
        },
      });

      expect(state.watchedEpisodes, 120);
      expect(state.status, MalStatus.watching);
      expect(state.totalEpisodes, 500);
      expect(state.isRewatching, isTrue);
      expect(state.isNew, isFalse);
    });

    // An anime the user has never added comes back with no my_list_status at
    // all. That is the normal first-write case, not an error.
    test('an anime that is not on the list reads as new, at zero', () {
      final state = MalEntryState.fromAnime(const {
        'id': 1735,
        'num_episodes': 12,
      });

      expect(state.watchedEpisodes, 0);
      expect(state.status, isNull);
      expect(state.isNew, isTrue);
      expect(state.isRewatching, isFalse);
    });

    // MAL reports 0 episodes for a show that is still airing. Carrying that
    // through as a real total would make every episode look like the last one.
    test('a zero episode count is treated as unknown, not as zero', () {
      final state = MalEntryState.fromAnime(const {
        'id': 1,
        'num_episodes': 0,
      });

      expect(state.totalEpisodes, isNull);
    });
  });

  group('MalAnime', () {
    test('search titles collect english, japanese and synonyms without blanks', () {
      final anime = MalAnime.fromJson(const {
        'id': 21,
        'title': 'One Piece',
        'alternative_titles': {
          'en': '',
          'ja': 'ONE PIECE',
          'synonyms': ['One Piece', 'OP'],
        },
        'num_episodes': 1100,
      });

      // "One Piece" appears twice across title and synonyms, and the empty
      // English title must not become a candidate that matches nothing.
      expect(anime.searchTitles, ['One Piece', 'ONE PIECE', 'OP']);
      expect(anime.episodes, 1100);
    });
  });
}
