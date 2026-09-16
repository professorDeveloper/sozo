import 'package:flutter/material.dart';
import 'package:soplay/features/comments/presentation/widgets/comments_panel.dart';

class DetailCommentsTab extends StatelessWidget {
  const DetailCommentsTab({
    super.key,
    required this.provider,
    required this.contentUrl,
  });

  final String provider;
  final String contentUrl;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final tabsArea = padding.top + kToolbarHeight + kTextTabBarHeight + 36;
    final height = (size.height - tabsArea - padding.bottom).clamp(
      320.0,
      double.infinity,
    );
    return SizedBox(
      height: height,
      child: CommentsPanel(provider: provider, contentUrl: contentUrl),
    );
  }
}
