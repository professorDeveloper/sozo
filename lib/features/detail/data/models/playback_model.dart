import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/entities/playback_entity.dart';
import 'package:soplay/features/detail/domain/entities/source_notice.dart';
import 'episode_model.dart';
import 'thumbnails_model.dart';
import 'video_source_model.dart';

class PlaybackModel extends PlaybackEntity {
  const PlaybackModel({
    required super.provider,
    required super.contentUrl,
    required super.isSerial,
    required super.episodes,
    required super.videoSources,
    required super.playerSrc,
    required super.headers,
    super.type,
    super.thumbnails,
    super.page,
    super.size,
    super.total,
    super.totalPages,
    super.sort,
    super.playable,
    super.notice,
  });

  factory PlaybackModel.fromJson(Map<String, dynamic> json) {
    final episodes = (json['episodes'] as List? ?? [])
        .map((e) => EpisodeModel.fromJson(e as Map<String, dynamic>))
        .toList();

    final videoSources = (json['videoSources'] as List? ?? [])
        .map((e) => VideoSourceModel.fromJson(e as Map<String, dynamic>))
        .toList();

    final src = json['playerSrc'] as String?;
    final typeRaw = json['type'] as String?;

    return PlaybackModel(
      provider: json['provider'] as String? ?? '',
      contentUrl: json['contentUrl'] as String? ?? '',
      isSerial: json['isSerial'] as bool? ?? false,
      episodes: episodes,
      videoSources: videoSources,
      playerSrc: src == null || src.isEmpty ? null : src,
      type: typeRaw == null || typeRaw.isEmpty ? null : typeRaw.toLowerCase(),
      headers: _parseHeaders(json['headers']),
      thumbnails: ThumbnailsModel.fromJson(json['thumbnails']),
      page: (json['page'] as num?)?.toInt() ?? 1,
      size: (json['size'] as num?)?.toInt() ?? 100,
      total: (json['total'] as num?)?.toInt() ?? episodes.length,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 1,
      sort: (json['sort'] as String?)?.toLowerCase() ?? 'asc',
      // A source that says nothing about playability is taken at its word that
      // there is nothing to say; only `false` means "do not start a player".
      playable: json['playable'] as bool? ?? true,
      // Two spellings for one fact. `noticeCode` is on every answer that
      // carries a notice; `playableReason` only on the ones that also set
      // `playable: false`, and it holds the same token — so either will do and
      // the first one present wins.
      notice:
          SourceNotice.read(json['noticeCode'] as String?) ??
          SourceNotice.read(json['playableReason'] as String?),
    );
  }

  /// Same playback with a different episode ordering.
  ///
  /// Sorting used to mutate `episodes` in place, which throws on any model
  /// built from a const list — and silently reorders a list another screen may
  /// still be holding. Returning a new model keeps sorting a pure operation.
  PlaybackModel copyWithEpisodes(List<EpisodeEntity> episodes) => PlaybackModel(
    provider: provider,
    contentUrl: contentUrl,
    isSerial: isSerial,
    episodes: episodes,
    videoSources: videoSources,
    playerSrc: playerSrc,
    type: type,
    headers: headers,
    thumbnails: thumbnails,
    page: page,
    size: size,
    total: total,
    totalPages: totalPages,
    sort: sort,
    playable: playable,
    notice: notice,
  );

  static Map<String, String> _parseHeaders(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    raw.forEach((k, v) {
      if (k is String && v != null) out[k] = v.toString();
    });
    return out;
  }
}
