import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/comments/domain/entities/comment_author.dart';

class CommentAvatar extends StatelessWidget {
  const CommentAvatar({super.key, required this.author, this.size = 36});
  final CommentAuthor author;
  final double size;

  String get _initials {
    final source = author.nameOrUsername.trim();
    if (source.isEmpty) return '?';
    final parts = source.split(RegExp(r'\s+'));
    if (parts.length > 1 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return source[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final url = author.photoURL;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceVariant,
        border: Border.all(color: AppColors.border, width: 0.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: url != null && url.isNotEmpty
          ? Image.network(
              url,
              fit: BoxFit.cover,
              cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              errorBuilder: (_, _, _) => _placeholder(),
              loadingBuilder: (_, child, chunk) =>
                  chunk == null ? child : _placeholder(),
            )
          : _placeholder(),
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.surfaceVariant,
        alignment: Alignment.center,
        child: Text(
          _initials,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: size * 0.38,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}
