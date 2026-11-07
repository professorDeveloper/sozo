part of 'comments_bloc.dart';

abstract class CommentsEvent {
  const CommentsEvent();
}

class CommentsInit extends CommentsEvent {
  final String provider;
  final String contentUrl;

  /// Null keeps the title-level thread.
  final String? episodeKey;
  const CommentsInit({
    required this.provider,
    required this.contentUrl,
    this.episodeKey,
  });
}

class CommentsRefresh extends CommentsEvent {
  const CommentsRefresh();
}

class CommentsLoadMore extends CommentsEvent {
  const CommentsLoadMore();
}

class CommentsToggleReplies extends CommentsEvent {
  final String commentId;
  const CommentsToggleReplies(this.commentId);
}

class CommentsLoadReplies extends CommentsEvent {
  final String commentId;
  const CommentsLoadReplies(this.commentId);
}

class CommentsCreate extends CommentsEvent {
  final String text;
  final String? parentId;
  final bool spoiler;
  final int? atSec;
  const CommentsCreate({
    required this.text,
    this.parentId,
    this.spoiler = false,
    this.atSec,
  });
}

class CommentsEdit extends CommentsEvent {
  final String id;
  final String text;

  /// Null leaves the flag as it was.
  final bool? spoiler;
  const CommentsEdit({required this.id, required this.text, this.spoiler});
}

class CommentsDelete extends CommentsEvent {
  final String id;
  const CommentsDelete(this.id);
}

class CommentsToggleLike extends CommentsEvent {
  final String id;
  const CommentsToggleLike(this.id);
}
