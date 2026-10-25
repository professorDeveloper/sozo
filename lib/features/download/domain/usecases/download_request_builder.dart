import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/player/source_ladder.dart';
import 'package:soplay/features/detail/domain/download_choices.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/entities/media_resolve_entity.dart';
import 'package:soplay/features/detail/domain/entities/subtitle_entity.dart';
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

  /// The source answered the url with a web page, not the video: a challenge,
  /// an error or a home page served as success. Queued, it failed minutes
  /// later in the list; another server is the way out.
  webPage,
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
    Future<MediaResolveEntity?> Function(MediaResolveEntity)? resolveEmbed,
    Future<bool> Function(MediaResolveEntity)? canDownload,
    Future<bool> Function(MediaResolveEntity)? servesWebPage,
  }) : _resolve = resolve,
       _getPages = getPages,
       _resolveEmbed = resolveEmbed,
       _canDownload = canDownload,
       _servesWebPage = servesWebPage;

  final ResolveMediaUseCase _resolve;
  final GetPagesUseCase _getPages;
  final Future<MediaResolveEntity?> Function(MediaResolveEntity)? _resolveEmbed;

  final Future<bool> Function(MediaResolveEntity)? _canDownload;

  /// True only for a definite web page (see `DownloadMediaProbe`): a probe
  /// that got no answer says nothing about the file and must not block it.
  final Future<bool> Function(MediaResolveEntity)? _servesWebPage;

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
    return prepareVideo(result.value);
  }

  /// Both film and episode downloads must turn an embed into media first.
  Future<VideoResolution> prepareVideo(MediaResolveEntity media) async {
    bool direct(MediaResolveEntity item) => DownloadChoices.isDownloadableUrl(
      url: item.videoUrl,
      type: item.type,
      hasDirective: item.extractor != null,
    );
    // Plain direct downloads keep their existing path. Mixed embed/direct
    // results need validation: backend-issued tokens can be IP-bound or stale.
    final hasEmbeds =
        !direct(media) ||
        media.videoSources.any(
          (s) => !DownloadChoices.isDownloadableUrl(
            url: s.videoUrl,
            type: s.type,
            hasDirective: false,
          ),
        );
    if (!hasEmbeds) {
      // A direct url is still only the provider's word. One that answers with
      // a web page used to be queued anyway and fail minutes later as "a web
      // page"; 2 KB says so before anything is queued. The mirror asked is
      // the one a download takes by default, not whatever was listed first.
      final pick = quietPick(media);
      final probed = MediaResolveEntity(
        videoUrl: pick.url,
        headers: pick.headers,
        type: pick.type,
      );
      if (await _isWebPage(probed)) {
        return const VideoResolution.failed(DownloadBuildFailure.webPage);
      }
      return VideoResolution.resolved(media);
    }

    final candidates = <MediaResolveEntity>[];
    if (direct(media)) candidates.add(media);
    final ladder = SourceLadder(
      sources: media.videoSources,
      hasDirective: false,
    );
    final preferred = ladder.initialPick();
    final order = <int>[
      ?preferred,
      for (var i = 0; i < media.videoSources.length; i++)
        if (i != preferred) i,
    ];
    for (final i in order) {
      final source = media.videoSources[i];
      candidates.add(
        MediaResolveEntity(
          videoUrl: source.videoUrl,
          type: source.type,
          headers: source.headers.isEmpty ? media.headers : source.headers,
          subtitles: media.subtitles,
          videoSources: [source],
          // A sibling of unknown shape under a directive is an embed page like
          // the top-level one. Without the directive it counted as direct, was
          // probed, found to be HTML and skipped, instead of being sniffed.
          extractor: source.type == null ? media.extractor : null,
        ),
      );
    }
    if (!direct(media)) candidates.insert(0, media);
    // Direct candidates first, then each embed. Never let quietPick re-select
    // an unvalidated sibling from the original response after a fallback.
    final ordered = [
      ...candidates.where(direct),
      ...candidates.where((c) => !direct(c)),
    ];
    final seen = <String>{};
    for (final candidate in ordered) {
      if (!seen.add(candidate.videoUrl)) continue;
      try {
        final resolved = direct(candidate)
            ? candidate
            : await _resolveEmbed?.call(candidate);
        if (resolved == null || !direct(resolved)) continue;
        if (_canDownload != null && !await _canDownload(resolved)) continue;
        return VideoResolution.resolved(
          MediaResolveEntity(
            videoUrl: resolved.videoUrl,
            type: resolved.type,
            headers: resolved.headers,
            subtitles: resolved.subtitles,
            videoSources: resolved.videoSources
                .where((s) => s.videoUrl == resolved.videoUrl)
                .toList(),
          ),
        );
      } catch (_) {
        /* This mirror failed; try the next candidate. */
      }
    }
    return const VideoResolution.failed(DownloadBuildFailure.needsPlayback);
  }

  /// A probe that throws is no answer, and no answer never blocks a download.
  Future<bool> _isWebPage(MediaResolveEntity media) async {
    final probe = _servesWebPage;
    if (probe == null) return false;
    try {
      return await probe(media);
    } catch (_) {
      return false;
    }
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
      return DownloadSelection(
        url: media.videoUrl,
        headers: media.headers,
        type: media.type,
      );
    }
    final source = sources[pick];
    return DownloadSelection(
      url: source.videoUrl,
      headers: source.headers.isNotEmpty ? source.headers : media.headers,
      height: source.height,
      type: source.type,
    );
  }

  static DownloadRequest videoRequest(
    DownloadTitle title,
    EpisodeEntity ep,
    DownloadSelection selection, {
    List<SubtitleEntity> subtitles = const [],
  }) => DownloadRequest.video(
    contentUrl: title.contentUrl,
    provider: title.provider,
    title: title.title,
    sourceUrl: selection.url,
    videoHeight: selection.height,
    type: selection.type,
    thumbnailUrl: title.thumbnail,
    headers: selection.headers,
    isSerial: true,
    episodeNumber: ep.episode,
    episodeLabel: ep.label,
    subtitles: subtitles,
  );

  /// Resolve, check and pick without asking anyone.
  Future<DownloadBuild> quietVideo(
    DownloadTitle title,
    EpisodeEntity ep,
  ) async {
    final resolved = await resolveVideo(ep, provider: title.provider);
    final media = resolved.media;
    if (media == null) return DownloadBuild.failed(resolved.failure!);
    return DownloadBuild.ready(
      videoRequest(title, ep, quietPick(media), subtitles: media.subtitles),
    );
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
