import 'package:dio/dio.dart';
import 'package:soplay/features/comments/data/models/comment_list_model.dart';
import 'package:soplay/features/comments/data/models/comment_model.dart';
import 'package:soplay/features/comments/domain/entities/like_result.dart';

class CommentsDataSource {
  final Dio dio;
  const CommentsDataSource({required this.dio});

  Future<CommentListModel> getComments({
    required String provider,
    required String contentUrl,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await dio.get(
      '/comments',
      queryParameters: {
        'provider': provider,
        'contentUrl': contentUrl,
        'page': page,
        'limit': limit,
      },
    );
    return CommentListModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<CommentListModel> getReplies({
    required String parentId,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await dio.get(
      '/comments/$parentId/replies',
      queryParameters: {'page': page, 'limit': limit},
    );
    return CommentListModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<CommentModel> create({
    required String provider,
    required String contentUrl,
    required String text,
    String? parentId,
  }) async {
    final payload = <String, dynamic>{
      'provider': provider,
      'contentUrl': contentUrl,
      'text': text,
    };
    if (parentId != null) payload['parentId'] = parentId;
    final res = await dio.post('/comments', data: payload);
    final body = res.data as Map<String, dynamic>;
    return CommentModel.fromJson(
      (body['item'] as Map).cast<String, dynamic>(),
    );
  }

  Future<CommentModel> edit({
    required String id,
    required String text,
  }) async {
    final res = await dio.put('/comments/$id', data: {'text': text});
    final body = res.data as Map<String, dynamic>;
    return CommentModel.fromJson(
      (body['item'] as Map).cast<String, dynamic>(),
    );
  }

  Future<int> delete(String id) async {
    final res = await dio.delete('/comments/$id');
    final body = res.data as Map<String, dynamic>;
    return (body['cascadeDeleted'] as num?)?.toInt() ?? 0;
  }

  Future<CommentListModel> getScopedComments({
    required String provider,
    required String contentUrl,
    String? episodeKey,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await dio.get(
      '/comments',
      queryParameters: {
        'provider': provider,
        'contentUrl': contentUrl,
        'episodeKey': ?episodeKey,
        'page': page,
        'limit': limit,
      },
    );
    return CommentListModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<CommentModel> createScoped({
    required String provider,
    required String contentUrl,
    required String text,
    String? parentId,
    String? episodeKey,
    bool spoiler = false,
    int? atSec,
  }) async {
    final res = await dio.post(
      '/comments',
      data: {
        'provider': provider,
        'contentUrl': contentUrl,
        'text': text,
        'parentId': ?parentId,
        'episodeKey': ?episodeKey,
        if (spoiler) 'spoiler': true,
        'atSec': ?atSec,
      },
    );
    final body = res.data as Map<String, dynamic>;
    return CommentModel.fromJson(
      (body['item'] as Map).cast<String, dynamic>(),
    );
  }

  Future<CommentModel> editScoped({
    required String id,
    required String text,
    bool? spoiler,
  }) async {
    final res = await dio.put(
      '/comments/$id',
      data: {'text': text, 'spoiler': ?spoiler},
    );
    final body = res.data as Map<String, dynamic>;
    return CommentModel.fromJson(
      (body['item'] as Map).cast<String, dynamic>(),
    );
  }

  Future<Map<String, int>> episodeCounts({
    required String provider,
    required String contentUrl,
  }) async {
    final res = await dio.get(
      '/comments/episode-counts',
      queryParameters: {'provider': provider, 'contentUrl': contentUrl},
    );
    final counts = (res.data as Map?)?['counts'];
    if (counts is! Map) return const {};
    return {
      for (final e in counts.entries)
        if (e.value is num) e.key.toString(): (e.value as num).toInt(),
    };
  }

  Future<LikeResult> toggleLike(String id) async {
    final res = await dio.post('/comments/$id/like');
    final body = res.data as Map<String, dynamic>;
    return LikeResult(
      liked: body['liked'] as bool? ?? false,
      likeCount: (body['likeCount'] as num?)?.toInt() ?? 0,
    );
  }
}
