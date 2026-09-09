/// Everything Sozo can infer from a torrent's *file name* alone.
///
/// Anime releases follow a naming convention that is remarkably consistent
/// across groups, and it is the only quality signal a tracker gives us before
/// the torrent is opened — Nyaa's RSS carries no resolution, codec or audio
/// field. Parsing the name is therefore what makes "1080p only", "no
/// mini-encodes" and "prefer dual audio" filters possible at all.
///
/// The vocabulary here is taken from the release-name anatomy documented at
/// <https://wotaku.wiki/torrenting/nyaa>.
library;

/// Where the video ultimately came from, best quality first.
///
/// The ordering is deliberate: [compareTo] on the enum index is used to rank
/// two otherwise-equal releases, and a remux always beats a re-encode.
enum ReleaseSource {
  /// Disc source with no re-encoding. Highest quality, largest files.
  remux('Remux'),

  /// Raw Blu-ray disc image / container. Needs mounting, rarely useful on
  /// mobile, but it does mean untouched quality.
  bluRayDisc('BDISO/BDMV'),

  /// Encoded from a Blu-ray. The sweet spot for most archival releases.
  bluRayEncode('BDRip'),

  /// Untouched stream pulled from a streaming site. What SubsPlease and
  /// Erai-raws ship for currently-airing shows.
  webDl('WEB-DL'),

  /// Screen-captured or re-encoded from a streaming site.
  webRip('WEB-Rip'),

  /// Captured from broadcast TV.
  hdtv('HDTV'),

  dvd('DVD'),

  /// An encode of an existing encode — visible generational loss.
  reEncode('Re-Encode'),

  /// File size prioritised over everything else. The wiki calls the quality
  /// loss "severe"; we surface it so users can filter these out.
  miniEncode('Mini-Encode');

  const ReleaseSource(this.label);

  final String label;
}

enum VideoCodec {
  h264('x264'),
  h265('x265'),
  av1('AV1'),
  vp9('VP9');

  const VideoCodec(this.label);

  final String label;

  /// True for codecs that a meaningful share of low-end Android devices cannot
  /// decode in hardware at 1080p+. Used to warn before playback, not to hide.
  bool get isHeavy => this == VideoCodec.h265 || this == VideoCodec.av1;
}

enum AudioFormat {
  flac('FLAC', lossless: true),
  aac('AAC', lossless: false),
  ac3('AC3', lossless: false),
  eac3('EAC3', lossless: false),
  dts('DTS', lossless: false),
  opus('Opus', lossless: false),
  mp3('MP3', lossless: false);

  const AudioFormat(this.label, {required this.lossless});

  final String label;
  final bool lossless;
}

/// How subtitles are carried, which decides whether they can be turned off.
enum SubtitleKind {
  /// Soft subs — a separate track the player can toggle or restyle.
  closedCaptions('CC'),

  /// Burned into the video. Permanent; no track switching, no restyling.
  openCaptions('Hardsub'),

  /// Soft subs that also transcribe sound effects.
  sdh('SDH');

  const SubtitleKind(this.label);

  final String label;
}

/// The parsed form of a release file name.
///
/// Every field is nullable or empty-by-default on purpose: names in the wild
/// are inconsistent, and a half-parsed name is still far more useful than
/// none. Nothing here should ever throw — [ReleaseNameParser] is called on
/// every row of every search result.
class ReleaseInfo {
  const ReleaseInfo({
    this.group,
    this.showTitle,
    this.season,
    this.episode,
    this.episodeEnd,
    this.resolutionHeight,
    this.source,
    this.codec,
    this.audio = const {},
    this.bitDepth,
    this.crc32,
    this.container,
    this.subtitles,
    this.dualAudio = false,
    this.multiSubtitle = false,
    this.multiAudio = false,
    this.hdr = false,
    this.batch = false,
    this.uncensored = false,
  });

  /// The release group — `[SubsPlease]`, `[Erai-raws]`, `-VARYG`.
  final String? group;

  /// Best-effort show title with the group, tags and metadata stripped out.
  final String? showTitle;

  final int? season;

  /// Single episode number, or the first of a range.
  final int? episode;

  /// Set only for ranges such as `01-12`, which indicate a batch.
  final int? episodeEnd;

  /// Vertical resolution in pixels — 1080 for `1080p` and for `1920x1080`.
  /// Stored as a number rather than a label so `>= 1080` filters are trivial.
  final int? resolutionHeight;

  final ReleaseSource? source;
  final VideoCodec? codec;

  /// Every audio format named in the title. Dual-audio releases routinely list
  /// two, which is why this is a set and not a single value.
  final Set<AudioFormat> audio;

  /// 8 or 10. 10-bit is the norm for modern anime encodes.
  final int? bitDepth;

  /// The CRC32 checksum most groups append, e.g. `[4277EF46]`.
  final String? crc32;

  /// `mkv` or `mp4`. MP4 implies hardsubs and a single audio track.
  final String? container;

  final SubtitleKind? subtitles;

  final bool dualAudio;
  final bool multiSubtitle;
  final bool multiAudio;
  final bool hdr;

  /// A season pack or episode range rather than a single episode. These need
  /// the file picker, since the torrent holds many playable files.
  final bool batch;

  final bool uncensored;

  /// Returns a copy with the given fields replaced.
  ///
  /// Used where a tracker states something authoritatively that the file name
  /// only implies. nekoBT's API, for instance, returns real `hardsub`, `batch`
  /// and release-group fields, and those should win over anything guessed from
  /// the title.
  ReleaseInfo copyWith({
    String? group,
    String? showTitle,
    int? season,
    int? episode,
    int? episodeEnd,
    int? resolutionHeight,
    ReleaseSource? source,
    VideoCodec? codec,
    Set<AudioFormat>? audio,
    int? bitDepth,
    String? crc32,
    String? container,
    SubtitleKind? subtitles,
    bool? dualAudio,
    bool? multiSubtitle,
    bool? multiAudio,
    bool? hdr,
    bool? batch,
    bool? uncensored,
  }) =>
      ReleaseInfo(
        group: group ?? this.group,
        showTitle: showTitle ?? this.showTitle,
        season: season ?? this.season,
        episode: episode ?? this.episode,
        episodeEnd: episodeEnd ?? this.episodeEnd,
        resolutionHeight: resolutionHeight ?? this.resolutionHeight,
        source: source ?? this.source,
        codec: codec ?? this.codec,
        audio: audio ?? this.audio,
        bitDepth: bitDepth ?? this.bitDepth,
        crc32: crc32 ?? this.crc32,
        container: container ?? this.container,
        subtitles: subtitles ?? this.subtitles,
        dualAudio: dualAudio ?? this.dualAudio,
        multiSubtitle: multiSubtitle ?? this.multiSubtitle,
        multiAudio: multiAudio ?? this.multiAudio,
        hdr: hdr ?? this.hdr,
        batch: batch ?? this.batch,
        uncensored: uncensored ?? this.uncensored,
      );

  /// `1080p`-style label rebuilt from [resolutionHeight], for display.
  String? get resolutionLabel =>
      resolutionHeight == null ? null : '${resolutionHeight}p';

  /// True when subtitles cannot be turned off or restyled.
  bool get hasHardsubs => subtitles == SubtitleKind.openCaptions;

  /// Short chips for the search row, in the order users scan them.
  List<String> get badges => [
        ?resolutionLabel,
        if (source != null) source!.label,
        if (codec != null) codec!.label,
        if (bitDepth == 10) '10bit',
        if (hdr) 'HDR',
        for (final a in audio) a.label,
        if (dualAudio) 'Dual Audio',
        if (multiSubtitle) 'Multi-Sub',
        if (hasHardsubs) 'Hardsub',
        if (batch) 'Batch',
        if (uncensored) 'Uncensored',
      ];
}
