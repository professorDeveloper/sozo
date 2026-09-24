import 'package:flutter/material.dart';

/// The opening of a chapter: its name set large, the book's name small, and
/// a rule under them. A fixed height, so the book layout can leave room for
/// it on the first page without measuring.
class NovelChapterHeader extends StatelessWidget {
  const NovelChapterHeader({
    super.key,
    required this.chapter,
    required this.book,
    required this.ink,
    required this.accent,
    this.fontFamily,
  });

  static const double height = 132;

  final String chapter;
  final String book;
  final Color ink;
  final Color accent;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => SizedBox(
        height: height,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: box.maxWidth,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (book.isNotEmpty)
                    Text(
                      book.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: ink.withValues(alpha: 0.5),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.6,
                      ),
                    ),
                  const SizedBox(height: 10),
                  Text(
                    chapter,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: ink,
                      fontFamily: fontFamily,
                      fontSize: 22,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _rule(false),
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      _rule(true),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rule(bool leftToRight) => Container(
    width: 56,
    height: 1,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          ink.withValues(alpha: leftToRight ? 0.35 : 0),
          ink.withValues(alpha: leftToRight ? 0 : 0.35),
        ],
      ),
    ),
  );
}
