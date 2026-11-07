import 'package:soplay/features/progress/domain/progress.dart';

class CommentAuthor {
  final String id;
  final String username;
  final String? displayName;
  final String? photoURL;
  final UserDecoration? decoration;

  const CommentAuthor({
    required this.id,
    required this.username,
    this.displayName,
    this.photoURL,
    this.decoration,
  });

  String get nameOrUsername =>
      (displayName?.trim().isNotEmpty ?? false) ? displayName! : username;
}
