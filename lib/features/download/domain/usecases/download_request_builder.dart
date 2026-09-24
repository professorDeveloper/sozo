import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/player/source_ladder.dart';
import 'package:soplay/features/detail/domain/download_choices.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/entities/media_resolve_entity.dart';
import 'package:soplay/features/detail/domain/usecases/get_pages_usecase.dart';
import 'package:soplay/features/detail/domain/usecases/resolve_media_usecase.dart';
import 'package:soplay/features/download/domain/entities/download_request.dart';
import 'package:soplay/features/download/domain/entities/download_selection.dart';
import 'package:soplay/features/manga/domain/entities/manga_pages_entity.dart';

/// The title a download belongs to.
class DownloadTitle {
  const DownloadTitle({
    required this.contentUrl,
    required this.provider,
    required this.title,
    this.thumbnail,
  });

  final String contentUrl;
  final String provider;
  final String title;
  final String? thumbnail;
}

enum DownloadBuildFailure {
  /// The provider did not give a stream, or did not answer.
  resolveFailed,

  /// Only an embed page came back; the stream appears after a WebView sniff,
  /// which only playback does.
  needsPlayback,

  /// The chapter's pages could not be listed.
  pagesFailed,
}

/// A resolved episode ready for a quality pick, or why there is none.
class VideoResolution {
  const VideoResolution.resolved(MediaResolveEntity this.media)
    : failure = null;
  const VideoResolution.failed(DownloadBuildFailure this.failure)
    : media = null;

  final MediaResolveEntity? media;
  final DownloadBuildFailure? failure;
}

class DownloadBuild {
  const DownloadBuild.ready(DownloadRequest this.request) : failure = null;
  const DownloadBuild.failed(DownloadBuildFailure this.failure)
    : request = null;

  final DownloadRequest? request;
  final DownloadBuildFailure? failure;
}

/// Turns an episode or chapter into a [DownloadRequest].
///
/// Shared by the episode list and the automation that downloads followed
/// titles by itself, so both resolve, reject embed pages and pick a mirror
/// the same way.
class DownloadRequestBuilder {
  const DownloadRequestBuilder({
    required ResolveMediaUseCase resolve,
    required GetPagesUseCase getPages,
  }) : _resolve = resolve,
       _getPages = getPages;

  final ResolveMediaUseCase _resolve;
  final GetPagesUseCase _getPages;

  /// The stream URL does not exist until the provider is asked for it, so a
  /// video download always starts with the same resolve the player makes.
  Future<VideoResolution> resolveVideo(
    EpisodeEntity ep, {
    required String provider,
  }) async {
    final result = await _resolve(ref: ep.mediaRef, provider: provider);
    if (result is! Success<MediaResolveEntity> ||
        result.value.videoUrl.isEmpty) {
      return const VideoResolution.failed(DownloadBuildFailure.resolveFailed);
    }
    final media = result.value;
    // A directive means `videoUrl` is the embed PAGE. Saving it would produce
    // an HTML file under a video's name that fails on first open.
    if (!DownloadChoices.isDownloadableUrl(
      url: media.videoUrl,
      type: media.type,
      hasDirective: media.extractor != null,
    )) {
      return const VideoResolution.failed(DownloadBuildFailure.needsPlayback);
    }
    return VideoResolution.resolved(media);
  }

  /// The mirror a download takes when nobody is asked.
  ///
  /// `media.videoUrl` is whatever the provider listed first, often its lowest
  /// quality, while the choice sheet and the player both pick through
  /// [SourceLadder].
  static DownloadSelection quietPick(MediaResolveEntity media) {
    final sources = media.videoSources;
    final pick = sources.isEmpty
        ? null
        : SourceLadder(sources: sources, hasDirective: false).initialPick();
    if (pick == null) {
      return DownloadSelection(url: media.videoUrl, headers: media.headers);
    }
    final source = sources[pick];
    return DownloadSelection(
      url: source.videoUrl,
      headers: source.headers.isNotEmpty ? source.headers : media.headers,
      height: source.height,
    );
  }

  static DownloadRequest videoRequest(
    DownloadTitle title,
    EpisodeEntity ep,
    DownloadSelection selection,
  ) => DownloadRequest.video(
    contentUrl: title.contentUrl,
    provider: title.provider,
    title: title.title,
    sourceUrl: selection.url,
    videoHeight: selection.height,
    thumbnailUrl: title.thumbnail,
    headers: selection.headers,
    isSerial: true,
    episodeNumber: ep.episode,
    episodeLabel: ep.label,
  );

  /// Resolve, check and pick without asking anyone.
  Future<DownloadBuild> quietVideo(
    DownloadTitle title,
    EpisodeEntity ep,
  ) async {
    final resolved = await resolveVideo(ep, provider: title.provider);
    final media = resolved.media;
    if (media == null) return DownloadBuild.failed(resolved.failure!);
    return DownloadBuild.ready(videoRequest(title, ep, quietPick(media)));
  }

  /// Pages are listed here rather than left to the queue, so a chapter whose
  /// pages cannot be listed is reported instead of sitting as "pending".
  Future<DownloadBuild> chapter(
    DownloadTitle title,
    EpisodeEntity ch, {
    int? chapterIndex,
  }) async {
    final result = await _getPages(ref: ch.mediaRef, provider: title.provider);
    if (result is! Success<MangaPagesEntity>) {
      return const DownloadBuild.failed(DownloadBuildFailure.pagesFailed);
    }
    final pages = result.value;
    return DownloadBuild.ready(
      DownloadRequest.mangaChapter(
        contentUrl: title.contentUrl,
        provider: title.provider,
        title: title.title,
        thumbnailUrl: title.thumbnail,
        headers: pages.headers,
        pageUrls: pages.pages.map((p) => p.imageUrl).toList(),
        imageHeaders: pages.pages
            .map(
              (p) => <String, String>{
                ...p.headers,
                if (p.cookie != null) 'Cookie': p.cookie!,
              },
            )
            .toList(),
        chapterRef: ch.mediaRef,
        chapterIndex: chapterIndex,
        episodeNumber: ch.episode,
        episodeLabel: ch.label,
      ),
    );
  }
}
