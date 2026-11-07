import 'package:soplay/features/comments/domain/entities/comment_entity.dart';
import 'comment_author_model.dart';

class CommentModel extends CommentEntity {
  const CommentModel({
    required super.id,
    required super.provider,
    required super.contentUrl,
    required super.text,
    required super.parentId,
    required super.user,
    required super.likeCount,
    required super.likedByMe,
    required super.edited,
    required super.replyCount,
    required super.createdAt,
    required super.updatedAt,
    super.episodeKey,
    super.spoiler,
    super.atSec,
  });

  factory CommentModel.fromJson(Map<String, dynamic> json) {
    DateTime parse(dynamic raw) {
      if (raw is String) {
        return DateTime.tryParse(raw)?.toLocal() ?? DateTime.now();
      }
      return DateTime.now();
    }

    return CommentModel(
      id: json['id'] as String? ?? json['_id'] as String? ?? '',
      provider: json['provider'] as String? ?? '',
      contentUrl: json['contentUrl'] as String? ?? '',
      text: json['text'] as String? ?? '',
      parentId: json['parentId'] as String?,
      user: CommentAuthorModel.fromJson(
        (json['user'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      likedByMe: json['likedByMe'] as bool? ?? false,
      edited: json['edited'] as bool? ?? false,
      replyCount: (json['replyCount'] as num?)?.toInt() ?? 0,
      createdAt: parse(json['createdAt']),
      updatedAt: parse(json['updatedAt'] ?? json['createdAt']),
      episodeKey: json['episodeKey'] as String?,
      spoiler: json['spoiler'] as bool? ?? false,
      atSec: (json['atSec'] as num?)?.toInt(),
    );
  }
}
