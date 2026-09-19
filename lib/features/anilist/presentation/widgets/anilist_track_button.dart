import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/anilist/data/anilist_link_store.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_link_sheet.dart';

/// The "track this on AniList" affordance on a title screen.
///
/// Renders NOTHING when AniList is not connected. A button that only explains
/// why it cannot work is worse than no button on a row that already holds six
/// actions — the place to connect is Profile → Connections, which the empty
/// states point at.
class AnilistTrackButton extends StatefulWidget {
  const AnilistTrackButton({
    super.key,
    required this.provider,
    required this.contentUrl,
    required this.title,
  });

  final String provider;
  final String contentUrl;
  final String title;

  @override
  State<AnilistTrackButton> createState() => _AnilistTrackButtonState();
}

class _AnilistTrackButtonState extends State<AnilistTrackButton> {
  final AnilistService _service = getIt<AnilistService>();
  final AnilistLinkStore _store = getIt<AnilistLinkStore>();

  AnilistLink? _link;

  @override
  void initState() {
    super.initState();
    _link = _store.get(widget.provider, widget.contentUrl);
    _service.addListener(_onChange);
  }

  @override
  void didUpdateWidget(covariant AnilistTrackButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The same button instance is reused when the page rebinds to another
    // title; without this it would keep showing the previous title's link.
    if (oldWidget.contentUrl != widget.contentUrl ||
        oldWidget.provider != widget.provider) {
      _link = _store.get(widget.provider, widget.contentUrl);
    }
  }

  @override
  void dispose() {
    _service.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _open() async {
    await AnilistLinkSheet.show(
      context,
      provider: widget.provider,
      contentUrl: widget.contentUrl,
      title: widget.title,
    );
    if (!mounted) return;
    setState(() => _link = _store.get(widget.provider, widget.contentUrl));
  }

  @override
  Widget build(BuildContext context) {
    if (!_service.isConnected || widget.contentUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    final linked = _link != null;
    return Tooltip(
      message: linked
          ? 'anilist.tracking_on'.tr()
          : 'anilist.track_on_anilist'.tr(),
      child: Material(
        color: linked
            ? kAnilistBlue.withValues(alpha: 0.18)
            : Colors.black.withValues(alpha: 0.35),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _open,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(
              linked
                  ? Icons.bookmark_added_rounded
                  : Icons.bookmark_add_outlined,
              size: 19,
              color: linked ? kAnilistBlue : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
