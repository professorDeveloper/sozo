import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/history/data/history_sync_remote_data_source.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';

void main() {
  test('a reader row keeps its media type through storage', () {
    const item = HistoryItem(
      contentUrl: 'https://m.test/1',
      provider: 'mn:x',
      title: 'Berserk',
      isSerial: true,
      episodeNumber: 12,
      watchedAt: 1,
      mediaType: 'manga',
    );
    final back = HistoryItem.fromJson(item.toJson());
    expect(back.mediaType, 'manga');
    expect(back.copyWith(positionMs: 5).mediaType, 'manga');
  });

  test('a video row stores no media type at all', () {
    const item = HistoryItem(
      contentUrl: 'https://v.test/1',
      provider: 'src',
      title: 'Frieren',
      watchedAt: 1,
    );
    expect(item.toJson().containsKey('mediaType'), isFalse);
  });

  test('only a TV row counts as foreign', () {
    const phone = HistorySyncItem(
      provider: 'mn:x',
      contentUrl: 'https://m.test/1',
      extra: {'mediaType': 'novel'},
    );
    expect(phone.isForeign, isFalse);
    expect(phone.mediaType, 'novel');
    expect(phone.toJson()['extra'], {'mediaType': 'novel'});

    const plain = HistorySyncItem(provider: 'src', contentUrl: 'u');
    expect(plain.isForeign, isFalse);
    expect(plain.mediaType, isNull);

    const tv = HistorySyncItem(
      provider: 'src',
      contentUrl: 'stream',
      extra: {'movieId': 7, 'mediaType': 'video'},
    );
    expect(tv.isForeign, isTrue);
  });
}
