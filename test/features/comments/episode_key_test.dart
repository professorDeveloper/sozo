import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/comments/domain/episode_key.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';

void main() {
  test('a film has no episode key and reacts under the empty one', () {
    expect(EpisodeKey.of(isSerial: false, episodeNumber: 3), isNull);
    expect(EpisodeKey.forReactions(null), '');
  });

  test('an episode is keyed by its number, else its index, like history', () {
    expect(EpisodeKey.of(isSerial: true, episodeNumber: 12), 'e12');
    expect(EpisodeKey.of(isSerial: true, episodeIndex: 4), 'e4');
    expect(
      EpisodeKey.of(isSerial: true, episodeNumber: 7, episodeIndex: 2),
      'e7',
    );
    expect(EpisodeKey.of(isSerial: true), isNull);

    final storage = HistoryItem.buildStorageKey(
      contentUrl: 'u',
      isSerial: true,
      episodeNumber: 7,
      episodeIndex: 2,
    );
    expect(storage.endsWith('::7'), isTrue);
  });

  test('the number round-trips', () {
    expect(EpisodeKey.numberOf('e12'), 12);
    expect(EpisodeKey.numberOf(null), isNull);
    expect(EpisodeKey.numberOf('s1e2'), isNull);
    expect(EpisodeKey.numberOf('ex'), isNull);
  });
}
