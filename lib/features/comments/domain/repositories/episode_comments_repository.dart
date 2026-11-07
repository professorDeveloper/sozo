import 'package:soplay/core/error/result.dart';
import '../entities/comment_entity.dart';
import '../entities/comment_list.dart';

/// Episode threads and spoiler flags.
///
/// Separate from [CommentsRepository] so the fakes that implement that one
/// keep compiling; [CommentsBloc] uses this when its repository offers it.
abstract class EpisodeCommentsRepository {
  Future<Result<CommentList>> getScopedComments({
    required String provider,
    required String contentUrl,
    String? episodeKey,
    int page,
    int limit,
  });

  Future<Result<CommentEntity>> createScoped({
    required String provider,
    required String contentUrl,
    required String text,
    String? parentId,
    String? episodeKey,
    bool spoiler,
    int? atSec,
  });

  Future<Result<CommentEntity>> editScoped({
    required String id,
    required String text,
    bool? spoiler,
  });

  /// Top-level comment count per episode key.
  Future<Result<Map<String, int>>> episodeCounts({
    required String provider,
    required String contentUrl,
  });
}
