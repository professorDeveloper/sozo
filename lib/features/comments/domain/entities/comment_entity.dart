import 'comment_author.dart';

class CommentEntity {
  final String id;
  final String provider;
  final String contentUrl;
  final String text;
  final String? parentId;
  final CommentAuthor user;
  final int likeCount;
  final bool likedByMe;
  final bool edited;
  final int replyCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Null for a title-level comment.
  final String? episodeKey;
  final bool spoiler;

  /// The second of the episode the comment was written at, when it was
  /// written from the player.
  final int? atSec;

  const CommentEntity({
    required this.id,
    required this.provider,
    required this.contentUrl,
    required this.text,
    required this.parentId,
    required this.user,
    required this.likeCount,
    required this.likedByMe,
    required this.edited,
    required this.replyCount,
    required this.createdAt,
    required this.updatedAt,
    this.episodeKey,
    this.spoiler = false,
    this.atSec,
  });

  bool get isTopLevel => parentId == null;

  CommentEntity copyWith({
    String? text,
    int? likeCount,
    bool? likedByMe,
    bool? edited,
    int? replyCount,
    DateTime? updatedAt,
    bool? spoiler,
  }) =>
      CommentEntity(
        id: id,
        provider: provider,
        contentUrl: contentUrl,
        text: text ?? this.text,
        parentId: parentId,
        user: user,
        likeCount: likeCount ?? this.likeCount,
        likedByMe: likedByMe ?? this.likedByMe,
        edited: edited ?? this.edited,
        replyCount: replyCount ?? this.replyCount,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        episodeKey: episodeKey,
        spoiler: spoiler ?? this.spoiler,
        atSec: atSec,
      );
}
