import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/entities/media_resolve_entity.dart';
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
        ),
      ),
    ).quietVideo(_title, _ep);
    final r = built.request!;
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

  test('a chapter whose pages fail is pagesFailed', () async {
    final built = await _builder().chapter(_title, _ep);
    expect(built.failure, DownloadBuildFailure.pagesFailed);
  });
}
