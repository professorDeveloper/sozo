import 'package:soplay/features/comments/domain/entities/comment_author.dart';
import 'package:soplay/features/progress/domain/progress.dart';

class CommentAuthorModel extends CommentAuthor {
  const CommentAuthorModel({
    required super.id,
    required super.username,
    super.displayName,
    super.photoURL,
    super.decoration,
  });

  factory CommentAuthorModel.fromJson(Map<String, dynamic> json) =>
      CommentAuthorModel(
        id: json['id'] as String? ?? json['_id'] as String? ?? '',
        username: json['username'] as String? ?? '',
        displayName: json['displayName'] as String?,
        photoURL: json['photoURL'] as String?,
        decoration: UserDecoration.fromJson(json),
      );
}
