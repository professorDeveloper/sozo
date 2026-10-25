import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/entities/extractor_config_entity.dart';
import 'package:soplay/features/detail/domain/entities/media_resolve_entity.dart';
import 'package:soplay/features/detail/domain/entities/subtitle_entity.dart';
import 'package:soplay/features/detail/domain/entities/video_source_entity.dart';
import 'package:soplay/features/detail/domain/usecases/get_pages_usecase.dart';
import 'package:soplay/features/detail/domain/usecases/resolve_media_usecase.dart';
import 'package:soplay/features/download/domain/entities/download_kind.dart';
import 'package:soplay/features/download/domain/entities/download_request.dart';
import 'package:soplay/features/download/domain/usecases/download_request_builder.dart';
import 'package:soplay/features/manga/domain/entities/manga_page_entity.dart';
import 'package:soplay/features/manga/domain/entities/manga_pages_entity.dart';

class _Resolve implements ResolveMediaUseCase {
  _Resolve(this.answer);
  Result<MediaResolveEntity> answer;
  final refs = <String>[];

  @override
  Future<Result<MediaResolveEntity>> call({
    required String ref,
    required String provider,
    String? lang,
  }) async {
    refs.add(ref);
    return answer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Pages implements GetPagesUseCase {
  _Pages(this.answer);
  Result<MangaPagesEntity> answer;

  @override
  Future<Result<MangaPagesEntity>> call({
    required String ref,
    required String provider,
  }) async => answer;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _title = DownloadTitle(
  contentUrl: 'https://src/show',
  provider: 'p1',
  title: 'Show',
  thumbnail: 'https://img/p.jpg',
);
const _ep = EpisodeEntity(episode: 7, label: 'Ep 7', mediaRef: 'ref-7');

VideoSourceEntity _source(String quality, int height, {String? url}) =>
    VideoSourceEntity(
      quality: quality,
      videoUrl: url ?? 'https://cdn/$height.m3u8',
      isDefault: false,
      accessible: true,
      height: height,
      type: 'hls',
      headers: {'Referer': 'r$height'},
    );

DownloadRequestBuilder _builder({
  Result<MediaResolveEntity>? media,
  Result<MangaPagesEntity>? pages,
}) => DownloadRequestBuilder(
  resolve: _Resolve(media ?? Failure(Exception('x'))),
  getPages: _Pages(pages ?? Failure(Exception('x'))),
);

void main() {
  test(
    'film and episode embeds are extracted before enqueueing media',
    () async {
      var sniffed = 0;
      final builder = DownloadRequestBuilder(
        resolve: _Resolve(
          const Success(
            MediaResolveEntity(
              videoUrl: 'https://luluvdoo.test/e/movie',
              headers: {},
              type: 'iframe',
            ),
          ),
        ),
        getPages: _Pages(Failure(Exception('unused'))),
        resolveEmbed: (media) async {
          sniffed++;
          expect(media.type, 'iframe');
          return const MediaResolveEntity(
            videoUrl: 'https://cdn.test/playlist/token',
            headers: {'Referer': 'https://luluvdoo.test/'},
            type: 'hls',
          );
        },
      );
      final built = await builder.quietVideo(_title, _ep);
      expect(sniffed, 1);
      expect(built.request!.kind, DownloadKind.hls);
      expect(built.request!.sourceUrl, 'https://cdn.test/playlist/token');
      expect(built.request!.headers['Referer'], 'https://luluvdoo.test/');
    },
  );

  test(
    'rejected direct and embed mirrors fall through to a verified download',
    () async {
      final tried = <String>[];
      final builder = DownloadRequestBuilder(
        resolve: _Resolve(Failure(Exception('unused'))),
        getPages: _Pages(Failure(Exception('unused'))),
        canDownload: (media) async => !media.videoUrl.contains('expired'),
        resolveEmbed: (media) async {
          tried.add(media.videoUrl);
          return MediaResolveEntity(
            videoUrl: media.videoUrl.contains('dead')
                ? 'https://cdn/expired.m3u8'
                : 'https://cdn/good.m3u8',
            headers: const {},
            type: 'hls',
          );
        },
      );
      final media = MediaResolveEntity(
        videoUrl: 'https://embed/dead',
        headers: const {},
        type: 'iframe',
        videoSources: [
          _source('1080p', 1080, url: 'https://cdn/expired.m3u8'),
          const VideoSourceEntity(
            quality: 'alternative',
            videoUrl: 'https://embed/good',
            isDefault: false,
            accessible: true,
            type: 'iframe',
          ),
        ],
      );
      final result = await builder.prepareVideo(media);
      expect(result.media!.videoUrl, 'https://cdn/good.m3u8');
      expect(
        DownloadRequestBuilder.quietPick(result.media!).url,
        'https://cdn/good.m3u8',
      );
      expect(tried, ['https://embed/dead', 'https://embed/good']);
    },
  );

  test('a direct mirror is used before sniffing an embed default', () async {
    final media = MediaResolveEntity(
      videoUrl: 'https://embed.test/page',
      headers: const {},
      type: 'iframe',
      videoSources: [_source('720p', 720)],
    );
    final prepared = await _builder().prepareVideo(media);
    expect(prepared.media!.videoUrl, 'https://cdn/720.m3u8');
  });

  test(
    'extensionless HLS keeps its format when queued for offline playback',
    () async {
      final built = await _builder(
        media: const Success(
          MediaResolveEntity(
            videoUrl: 'https://og.bakayaro.live/m3u8/token',
            headers: {},
            type: 'hls',
          ),
        ),
      ).quietVideo(_title, _ep);
      expect(built.request!.kind, DownloadKind.hls);
    },
  );

  test('an empty or failed resolve is resolveFailed', () async {
    final failed = await _builder().quietVideo(_title, _ep);
    expect(failed.failure, DownloadBuildFailure.resolveFailed);
    final empty = await _builder(
      media: const Success(MediaResolveEntity(videoUrl: '', headers: {})),
    ).quietVideo(_title, _ep);
    expect(empty.failure, DownloadBuildFailure.resolveFailed);
  });

  test('an embed page is refused as needsPlayback', () async {
    final built = await _builder(
      media: const Success(
        MediaResolveEntity(
          videoUrl: 'https://embed/page',
          headers: {},
          type: 'iframe',
        ),
      ),
    ).quietVideo(_title, _ep);
    expect(built.request, isNull);
    expect(built.failure, DownloadBuildFailure.needsPlayback);
  });

  test('the quiet pick goes through the ladder with the mirror headers', () {
    final media = MediaResolveEntity(
      videoUrl: 'https://cdn/first.m3u8',
      headers: const {'Referer': 'top'},
      videoSources: [_source('360p', 360), _source('1080p', 1080)],
    );
    final pick = DownloadRequestBuilder.quietPick(media);
    expect(pick.height, 1080);
    expect(pick.url, 'https://cdn/1080.m3u8');
    expect(pick.headers, {'Referer': 'r1080'});
  });

  test('no sources falls back to the top-level url and headers', () {
    const media = MediaResolveEntity(
      videoUrl: 'https://cdn/only.mp4',
      headers: {'Referer': 'top'},
    );
    final pick = DownloadRequestBuilder.quietPick(media);
    expect(pick.url, 'https://cdn/only.mp4');
    expect(pick.headers, {'Referer': 'top'});
    expect(pick.height, isNull);
  });

  test('a quiet video request carries the ids the episode list uses', () async {
    final built = await _builder(
      media: const Success(
        MediaResolveEntity(
          videoUrl: 'https://cdn/a.mp4',
          headers: {},
          type: 'mp4',
          subtitles: [
            SubtitleEntity(label: 'English', file: 'https://s/en.vtt'),
          ],
        ),
      ),
    ).quietVideo(_title, _ep);
    final r = built.request!;
    // Offline there is no subtitle search, so the tracks travel with it.
    expect(r.subtitles.single.label, 'English');
    expect(
      r.id,
      DownloadRequest.videoId(contentUrl: _title.contentUrl, episodeNumber: 7),
    );
    expect(r.isSerial, isTrue);
    expect(r.episodeNumber, 7);
    expect(r.episodeLabel, 'Ep 7');
    expect(r.thumbnailUrl, _title.thumbnail);
  });

  test('a chapter carries per-page headers with the page cookie', () async {
    final built = await _builder(
      pages: const Success(
        MangaPagesEntity(
          headers: {'Referer': 'site'},
          pages: [
            MangaPageEntity(
              index: 0,
              imageUrl: 'https://img/1.jpg',
              cookie: 'cf=1',
              headers: {'X': 'y'},
            ),
            MangaPageEntity(index: 1, imageUrl: 'https://img/2.jpg'),
          ],
        ),
      ),
    ).chapter(_title, _ep, chapterIndex: 3);
    final r = built.request!;
    expect(r.kind, DownloadKind.manga);
    expect(r.chapterRef, 'ref-7');
    expect(r.chapterIndex, 3);
    expect(r.pageUrls, ['https://img/1.jpg', 'https://img/2.jpg']);
    expect(r.imageHeaders.first, {'X': 'y', 'Cookie': 'cf=1'});
    expect(r.imageHeaders.last, isEmpty);
  });

  group('a plain direct result is probed at tap time', () {
    DownloadRequestBuilder probed(
      MediaResolveEntity media,
      Future<bool> Function(MediaResolveEntity) servesWebPage,
    ) => DownloadRequestBuilder(
      resolve: _Resolve(Success(media)),
      getPages: _Pages(Failure(Exception('unused'))),
      servesWebPage: servesWebPage,
    );

    const film = MediaResolveEntity(
      videoUrl: 'https://files.test/film.mp4',
      headers: {},
      type: 'mp4',
    );

    test('a web page fails as webPage before anything is queued', () async {
      final asked = <String>[];
      final built = await probed(film, (m) async {
        asked.add(m.videoUrl);
        return true;
      }).quietVideo(_title, _ep);
      expect(built.request, isNull);
      expect(built.failure, DownloadBuildFailure.webPage);
      expect(asked, ['https://files.test/film.mp4']);
    });

    test('the mirror asked is the one a download takes by default', () async {
      final asked = <String>[];
      final built = await probed(
        MediaResolveEntity(
          videoUrl: 'https://cdn/first.m3u8',
          headers: const {},
          type: 'hls',
          videoSources: [_source('360p', 360), _source('1080p', 1080)],
        ),
        (m) async {
          asked.add('${m.videoUrl} ${m.headers['Referer']}');
          return false;
        },
      ).quietVideo(_title, _ep);
      expect(asked, ['https://cdn/1080.m3u8 r1080']);
      expect(built.request!.sourceUrl, 'https://cdn/1080.m3u8');
    });

    test('anything short of a page queues as before', () async {
      final built = await probed(
        film,
        (_) async => false,
      ).quietVideo(_title, _ep);
      expect(built.request!.sourceUrl, 'https://files.test/film.mp4');
    });

    test('a probe that throws is no answer, and does not block', () async {
      final built = await probed(
        film,
        (_) async => throw Exception('socket closed'),
      ).quietVideo(_title, _ep);
      expect(built.request!.sourceUrl, 'https://files.test/film.mp4');
    });
  });

  test(
    'a sibling of unknown shape under a directive is sniffed, not taken as '
    'direct',
    () async {
      const directive = ExtractorConfigEntity(
        hostPattern: 'embed.test',
        urlPatterns: ['.m3u8'],
      );
      final sniffed = <String>[];
      final builder = DownloadRequestBuilder(
        resolve: _Resolve(Failure(Exception('unused'))),
        getPages: _Pages(Failure(Exception('unused'))),
        canDownload: (m) async => true,
        resolveEmbed: (m) async {
          sniffed.add(m.videoUrl);
          expect(m.extractor, same(directive));
          // The default page finds nothing; the sibling is the way in.
          if (m.videoUrl.endsWith('/1')) return null;
          return const MediaResolveEntity(
            videoUrl: 'https://cdn.test/sniffed.m3u8',
            headers: {},
            type: 'hls',
          );
        },
      );
      final result = await builder.prepareVideo(
        const MediaResolveEntity(
          videoUrl: 'https://embed.test/e/1',
          headers: {},
          type: 'iframe',
          extractor: directive,
          videoSources: [
            VideoSourceEntity(
              quality: 'mirror 2',
              videoUrl: 'https://embed.test/e/2',
              isDefault: false,
              accessible: true,
            ),
          ],
        ),
      );
      // It used to be handed to the downloader as the video itself.
      expect(sniffed, ['https://embed.test/e/1', 'https://embed.test/e/2']);
      expect(result.media!.videoUrl, 'https://cdn.test/sniffed.m3u8');
    },
  );

  test('a chapter whose pages fail is pagesFailed', () async {
    final built = await _builder().chapter(_title, _ep);
    expect(built.failure, DownloadBuildFailure.pagesFailed);
  });
}
