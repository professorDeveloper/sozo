import 'episode_entity.dart';
import 'extractor_config_entity.dart';
import 'thumbnails_entity.dart';
import 'video_source_entity.dart';

class PlayerArgs {
  final String title;
  final String provider;
  final String? contentUrl;
  final String? thumbnail;
  final String? movieUrl;
  final String? type;
  final List<VideoSourceEntity> videoSources;
  final Map<String, String> headers;
  final List<EpisodeEntity> episodes;
  final int initialEpisodeIndex;
  final String? initialLang;
  final Duration resumePosition;
  final bool showDownloadAction;
  final ThumbnailsEntity? thumbnails;

  // Watch2Gether identity: lets a movie carry its resolvable ref/lang and lets
  // the player know which party (if any) it belongs to. `provider` and
  // `contentUrl` already exist above.
  /// The sniff directive the server sent with this media, if any.
  ///
  /// The serial path re-resolves inside the player and picks this up on its
  /// own. The movie path resolves on the detail page and used to hand the
  /// player only the url, so a source whose url is an embed page — the whole
  /// point of the directive — reached ExoPlayer as HTML and failed with
  /// UnrecognizedInputFormatException. Carrying it here is what lets a hybrid
  /// movie play at all.
  final ExtractorConfigEntity? extractor;

  /// Live TV channel id, for the in-player programme guide.
  ///
  /// Live playback carried the stream url and the channel name but nothing that
  /// identified the channel, so the player could not ask for its guide — the
  /// one screen where "what am I watching, and what is next" is the actual
  /// question had no way to answer it.
  final String? liveChannelId;

  final String? mediaRef;
  final String? lang;
  final String? partyCode;

  /// Where [episodes] sits inside the whole run.
  ///
  /// ## Why the player needs to know
  ///
  /// The episodes screen loads one page at a time — a hundred entries — and
  /// used to hand the player exactly that list. Every "is there a next
  /// episode" question in the player then answered against a hundred, so
  /// opening episode 4 of a 1176-episode show meant Next went grey at 100,
  /// autoplay stopped, and there was no way out from inside the player. The
  /// list was never the series; it was the page of it that happened to be
  /// loaded.
  ///
  /// [windowStart] is the absolute index of `episodes[0]`, so the true
  /// position is `windowStart + episodeIndex`. Everything that INDEXES
  /// `episodes` stays window-relative; only the bounds and the page-crossing
  /// use these.
  ///
  /// Zero and an empty total mean "this list is the whole thing", which is
  /// what every caller that does not page gets by default.
  final int windowStart;

  /// How many episodes the series has in total, not how many are loaded.
  final int totalEpisodes;

  /// The page size the window was fetched with, so the player can ask for the
  /// next or previous page itself.
  final int pageSize;

  /// `asc` or `desc` — the order the window was fetched in, which decides
  /// which page is "next".
  final String sort;

  const PlayerArgs({
    required this.title,
    required this.provider,
    required this.headers,
    this.contentUrl,
    this.thumbnail,
    this.movieUrl,
    this.type,
    this.videoSources = const [],
    this.episodes = const [],
    this.initialEpisodeIndex = 0,
    this.initialLang,
    this.resumePosition = Duration.zero,
    this.showDownloadAction = true,
    this.thumbnails,
    this.extractor,
    this.liveChannelId,
    this.mediaRef,
    this.lang,
    this.partyCode,
    this.windowStart = 0,
    this.totalEpisodes = 0,
    this.pageSize = 0,
    this.sort = 'asc',
  });

  /// The number of episodes the player should behave as if it has.
  ///
  /// Falls back to the loaded list, so a caller that knows nothing about
  /// paging behaves exactly as before.
  int get effectiveTotal =>
      totalEpisodes > 0 ? totalEpisodes : episodes.length;

  /// Whether the loaded window is only part of the run.
  bool get isWindowed =>
      episodes.isNotEmpty && effectiveTotal > episodes.length;

  bool get isSerial => episodes.isNotEmpty;
}
