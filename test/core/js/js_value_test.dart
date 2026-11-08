// KissKH's device extractor answers as they reach the app on iPhone.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/js/js_value.dart';
import 'package:soplay/features/detail/data/models/detail_model.dart';
import 'package:soplay/features/detail/data/models/media_resolve_model.dart';
import 'package:soplay/features/detail/data/models/playback_model.dart';
import 'package:soplay/features/home/data/models/home_data_model.dart';
import 'package:soplay/features/home/data/models/view_all_paging_model.dart';
import 'package:soplay/features/search/data/model/search_model.dart';

void main() {
  final payloads =
      jsonDecode(
            File('test/fixtures/kisskh_extractor_v7.json').readAsStringSync(),
          )
          as Map<String, dynamic>;

  // WebKit's result crosses the platform channel through this codec, which
  // turns every JS object into a Map<Object?, Object?>.
  Object? overChannel(String key) => const StandardMessageCodec().decodeMessage(
    const StandardMessageCodec().encodeMessage(payloads[key]),
  );

  test('the channel really does hand over Map<Object?, Object?>', () {
    final home = overChannel('home') as Map;
    expect(home['sections'], isA<List>());
    expect(
      (home['sections'] as List).first,
      isNot(isA<Map<String, dynamic>>()),
    );
    // A shallow cast used to throw on the first card; the model now converts
    // nested maps itself.
    expect(
      HomeDataModel.fromJson(home.cast<String, dynamic>()).sections,
      hasLength(1),
    );
  });

  test('home, view-all and search parse', () {
    final home = HomeDataModel.fromJson(jsObjectFrom(overChannel('home'))!);
    expect(home.sections.single.label, 'Latest');
    expect(home.sections.single.items.first.title, isNotEmpty);
    expect(home.banner, hasLength(1));

    final page = ViewAllPagingModel.fromJson(
      jsObjectFrom(overChannel('category'))!,
    );
    expect(page.items, hasLength(2));
    expect(page.totalPages, 1384);

    final search = SearchModel.fromJson(jsObjectFrom(overChannel('search'))!);
    expect(search.items.first.title, 'Revenged Love');
  });

  test('detail and episodes parse', () {
    final detail = DetailModel.fromJson(jsObjectFrom(overChannel('detail'))!);
    expect(detail.title, 'Revenged Love');
    expect(detail.genres, ['TVSeries', 'Completed', 'China']);
    expect(detail.related.single.title, 'The First Frost');

    final eps = PlaybackModel.fromJson(jsObjectFrom(overChannel('episodes'))!);
    expect(eps.episodes.map((e) => e.mediaRef), [
      'kisskh:10826:185459',
      'kisskh:10826:185460',
    ]);
  });

  test('media keeps its sources and its ciphered subtitles', () {
    final media = MediaResolveModel.fromJson(
      jsObjectFrom(overChannel('media'))!,
    );
    expect(media.videoSources.single.type, 'hls');
    expect(media.headers['Referer'], 'https://kisskh.co/');
    expect(media.subtitles.map((s) => s.label), ['English', 'Indonesia']);
    final cipher = media.subtitles.first.cipher!;
    expect(cipher.key, 'AmSmZVcH93UQUezi');
    expect(cipher.iv, 'ReBKWW8cqdjPEnF6');
    expect(cipher.isSupported, isTrue);
  });

  test('Android JSON text and odd values', () {
    expect(
      jsObjectFrom(jsonEncode(payloads['detail']))!['title'],
      'Revenged Love',
    );
    expect(jsObjectFrom(null), isNull);
    expect(jsObjectFrom('null'), isNull);
    expect(jsObjectFrom('not json'), isNull);
    expect(jsObjectFrom(const [1, 2]), isNull);
  });
}
