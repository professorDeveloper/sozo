import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/trailer/trailer_service.dart';
import 'package:soplay/features/detail/domain/entities/detail_entity.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';
import 'package:soplay/features/detail/domain/entities/video_source_entity.dart';

/// The trailer button beside Play, shown only once a trailer has been found.
///
/// ## Why it appears rather than being there
///
/// A button that is always visible and sometimes says "no trailer found" is a
/// promise the page cannot keep; every title with no trailer becomes a dead
/// end somebody tapped. Nothing the page has when it loads settles it: a
/// provider without a TMDB id does not know whether a trailer exists until the
/// backend has matched the name, and even a named video may not be PLAYABLE —
/// one that has been taken down resolves to nothing. So the button waits for a
/// URL it can actually open, and appears only then.
class TrailerAction extends StatefulWidget {
  const TrailerAction({super.key, required this.detail});

  final DetailEntity detail;

  @override
  State<TrailerAction> createState() => _TrailerActionState();
}

class _TrailerActionState extends State<TrailerAction> {
  TrailerResult? _trailer;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    unawaited(_lookup());
  }

  Future<void> _lookup() async {
    // Which video this is, and whether there is one at all, is the service's
    // question: it has the catalogue's id when there is one and asks the
    // backend by name when there is not. A null answer leaves the button
    // absent, which is what it already did for a video that would not resolve.
    final result = await getIt<TrailerService>().resolveFor(
      widget.detail.trailerQuery,
    );
    if (!mounted) return;
    setState(() => _trailer = result);
  }

  void _open() {
    final trailer = _trailer;
    if (trailer == null || _opening) return;
    // Guard the double tap: these URLs take a moment to hand over to the
    // player, and two taps used to push two players onto the stack.
    setState(() => _opening = true);

    context.push(
      '/player',
      extra: PlayerArgs(
        title: trailer.title,
        provider: 'trailer',
        thumbnail: trailer.thumbnail,
        movieUrl: trailer.streamUrl,
        type: 'mp4',
        headers: const {},
        videoSources: [
          VideoSourceEntity(
            quality: 'Trailer',
            videoUrl: trailer.streamUrl,
            isDefault: true,
            accessible: true,
            type: 'mp4',
          ),
        ],
        // A trailer is not something to save, resume or count as watched. It
        // has no content url, so history has nothing to key on either.
        showDownloadAction: false,
      ),
    );

    // Re-enabled on the way back rather than after a delay, so the button is
    // never live while the player is still on screen.
    if (mounted) setState(() => _opening = false);
  }

  @override
  Widget build(BuildContext context) {
    // Reserve nothing while unresolved: the row lays out without this child,
    // and AnimatedSize on the parent would be the only way to avoid a jump.
    // Instead the widget itself animates from zero width, which keeps the
    // arrival to one place.
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: _trailer == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Tooltip(
                message: 'detail.trailer_action'.tr(),
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: Material(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _open,
                      child: Icon(
                        Icons.movie_outlined,
                        size: 21,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
