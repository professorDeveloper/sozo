import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/theme/kaizoku_colors.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/tracker/data/tracker_link_store.dart';

/// The local titles tied to a tracker entry, and a way to break a wrong tie.
///
/// This screen exists because automatic matching can be wrong. When it is, the
/// user needs to SEE that a link was made on their behalf and be able to undo
/// it — otherwise a bad guess keeps writing episodes into the wrong show with
/// no visible cause.
///
/// One screen for both trackers: the rows are the same shape, the action is the
/// same action, and only the store and the heading differ. A second copy would
/// be a second place for the unlink rule to drift.
class TrackerLinksPage extends StatefulWidget {
  const TrackerLinksPage({
    super.key,
    required this.store,
    required this.title,
    required this.accent,
  });

  final TrackerLinkStore store;

  /// The heading — the tracker's own name, already translated.
  final String title;

  /// The tracker's brand colour, used for the automatic-match chip.
  final Color accent;

  @override
  State<TrackerLinksPage> createState() => _TrackerLinksPageState();
}

class _TrackerLinksPageState extends State<TrackerLinksPage> {
  TrackerLinkStore get _store => widget.store;
  late List<TrackerLink> _items = _store.all();

  /// A row is the title itself, not just a record of a match — opening it is
  /// what people reach for first, and until now the only thing a tap could do
  /// was break the link.
  void _open(TrackerLink link) {
    if (link.contentUrl.trim().isEmpty) return;
    context.push(
      '/detail',
      extra: DetailArgs(
        contentUrl: link.contentUrl,
        provider: link.provider.trim().isEmpty ? null : link.provider.trim(),
      ),
    );
  }

  Future<void> _unlink(TrackerLink link) async {
    await _store.remove(link.provider, link.contentUrl);
    if (!mounted) return;
    setState(() => _items = _store.all());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('anilist.unlinked'.tr(args: [link.title])),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KaizokuColors.background,
      appBar: AppBar(
        backgroundColor: KaizokuColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: _items.isEmpty
          ? Center(
              child: AnilistStateMessage(
                icon: Icons.link_off_rounded,
                text: 'anilist.linked_titles_none'.tr(),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _LinkTile(
                link: _items[i],
                accent: widget.accent,
                onOpen: () => _open(_items[i]),
                onUnlink: () => _unlink(_items[i]),
              ),
            ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.link,
    required this.accent,
    required this.onOpen,
    required this.onUnlink,
  });

  final TrackerLink link;
  final Color accent;
  final VoidCallback onOpen;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KaizokuColors.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnilistCover(url: link.coverImage, width: 46, radius: 8),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      link.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: KaizokuColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        AnilistChip(
                          label: link.provider.isEmpty
                              ? '\u2014'
                              : link.provider,
                          color: KaizokuColors.textSecondary,
                        ),
                        if (link.auto)
                          AnilistChip(
                            label: 'anilist.auto_matched'.tr(),
                            icon: Icons.auto_fix_high_rounded,
                            color: accent,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'anilist.unlink'.tr(),
                onPressed: onUnlink,
                icon: const Icon(
                  Icons.link_off_rounded,
                  color: KaizokuColors.textHint,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
