import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/comments/presentation/widgets/comments_panel.dart';

/// One episode's comment thread, as a side panel where there is width for one
/// (landscape, TV, desktop) and a bottom sheet on a portrait phone.
///
/// Opened as a route so the thread's text field and its D-pad focus are its
/// own: the player's keyboard shortcuts never see the typing, and BACK closes
/// the thread rather than the player.
Future<void> showEpisodeComments(
  BuildContext context, {
  required String provider,
  required String contentUrl,
  required String? episodeKey,
  required String title,
  int? Function()? playheadSec,
}) {
  final size = MediaQuery.sizeOf(context);
  final side = isTvPlatform || isDesktopPlatform || size.width > size.height;
  final panel = EpisodeCommentsPanel(
    provider: provider,
    contentUrl: contentUrl,
    episodeKey: episodeKey,
    title: title,
    playheadSec: playheadSec,
  );
  if (!side) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SizedBox(height: size.height * 0.75, child: panel),
    );
  }
  // The panel sits on the end edge: it slides in from there, and the inset on
  // its inner edge is not its concern.
  final rtl = Directionality.of(context) == TextDirection.rtl;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black38,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, _, _) => Align(
      alignment: AlignmentDirectional.centerEnd,
      child: SizedBox(
        width: isTvPlatform ? 460 : 380,
        height: double.infinity,
        child: Material(
          color: AppColors.background,
          child: SafeArea(left: rtl, right: !rtl, child: panel),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween(begin: Offset(rtl ? -1 : 1, 0), end: Offset.zero).animate(
        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      ),
      child: child,
    ),
  );
}

class EpisodeCommentsPanel extends StatelessWidget {
  const EpisodeCommentsPanel({
    super.key,
    required this.provider,
    required this.contentUrl,
    required this.episodeKey,
    required this.title,
    this.playheadSec,
  });

  final String provider;
  final String contentUrl;
  final String? episodeKey;
  final String title;
  final int? Function()? playheadSec;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 4, 4),
          child: Row(
            children: [
              const Icon(
                Icons.forum_rounded,
                color: AppColors.textSecondary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'general.close'.tr(),
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(
                  Icons.close_rounded,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: CommentsPanel(
            provider: provider,
            contentUrl: contentUrl,
            episodeKey: episodeKey,
            playheadSec: playheadSec,
          ),
        ),
      ],
    );
  }
}
