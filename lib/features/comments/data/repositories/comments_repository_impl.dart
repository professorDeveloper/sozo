import 'package:dio/dio.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/comments/data/datasources/comments_data_source.dart';
import 'package:soplay/features/comments/domain/entities/comment_entity.dart';
import 'package:soplay/features/comments/domain/entities/comment_list.dart';
import 'package:soplay/features/comments/domain/entities/like_result.dart';
import 'package:soplay/features/comments/domain/repositories/comments_repository.dart';
import 'package:soplay/features/comments/domain/repositories/episode_comments_repository.dart';

class CommentsRepositoryImpl
    implements CommentsRepository, EpisodeCommentsRepository {
  final CommentsDataSource dataSource;
  const CommentsRepositoryImpl(this.dataSource);

  @override
  Future<Result<CommentList>> getComments({
    required String provider,
    required String contentUrl,
    int page = 1,
    int limit = 20,
  }) =>
      _wrap(() => dataSource.getComments(
            provider: provider,
            contentUrl: contentUrl,
            page: page,
            limit: limit,
          ));

  @override
  Future<Result<CommentList>> getReplies({
    required String parentId,
    int page = 1,
    int limit = 20,
  }) =>
      _wrap(() => dataSource.getReplies(
            parentId: parentId,
            page: page,
            limit: limit,
          ));

  @override
  Future<Result<CommentEntity>> create({
    required String provider,
    required String contentUrl,
    required String text,
    String? parentId,
  }) =>
      _wrap(() => dataSource.create(
            provider: provider,
            contentUrl: contentUrl,
            text: text,
            parentId: parentId,
          ));

  @override
  Future<Result<CommentEntity>> edit({
    required String id,
    required String text,
  }) =>
      _wrap(() => dataSource.edit(id: id, text: text));

  @override
  Future<Result<int>> delete(String id) => _wrap(() => dataSource.delete(id));

  @override
  Future<Result<CommentList>> getScopedComments({
    required String provider,
    required String contentUrl,
    String? episodeKey,
    int page = 1,
    int limit = 20,
  }) =>
      _wrap(() => dataSource.getScopedComments(
            provider: provider,
            contentUrl: contentUrl,
            episodeKey: episodeKey,
            page: page,
            limit: limit,
          ));

  @override
  Future<Result<CommentEntity>> createScoped({
    required String provider,
    required String contentUrl,
    required String text,
    String? parentId,
    String? episodeKey,
    bool spoiler = false,
    int? atSec,
  }) =>
      _wrap(() => dataSource.createScoped(
            provider: provider,
            contentUrl: contentUrl,
            text: text,
            parentId: parentId,
            episodeKey: episodeKey,
            spoiler: spoiler,
            atSec: atSec,
          ));

  @override
  Future<Result<CommentEntity>> editScoped({
    required String id,
    required String text,
    bool? spoiler,
  }) =>
      _wrap(() => dataSource.editScoped(id: id, text: text, spoiler: spoiler));

  @override
  Future<Result<Map<String, int>>> episodeCounts({
    required String provider,
    required String contentUrl,
  }) =>
      _wrap(() => dataSource.episodeCounts(
            provider: provider,
            contentUrl: contentUrl,
          ));

  @override
  Future<Result<LikeResult>> toggleLike(String id) =>
      _wrap(() => dataSource.toggleLike(id));

  Future<Result<T>> _wrap<T>(Future<T> Function() task) async {
    try {
      return Success(await task());
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401) return Failure(Exception('Please sign in first'));
      if (code == 403) return Failure(Exception('Not allowed'));
      if (code == 404) return Failure(Exception('Not found'));
      final data = e.response?.data;
      final raw = (data is Map ? data['message'] : null)?.toString() ??
          e.message ??
          'Something went wrong';
      return Failure(Exception(raw));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }
}
