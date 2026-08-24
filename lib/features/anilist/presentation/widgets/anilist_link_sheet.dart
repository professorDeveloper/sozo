import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/anilist/data/anilist_api.dart';
import 'package:soplay/features/anilist/data/anilist_link_store.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';

/// Attaches a locally-watched title to an AniList entry.
///
/// The manual counterpart to the tracker's exact-title matching, and the reason
/// tracking works at all for sources whose titles are transliterated, translated
/// or decorated — the user knows which show it is, and one tap is cheaper than
/// any matching heuristic that would guess wrong.
class AnilistLinkSheet extends StatefulWidget {
  const AnilistLinkSheet({
    super.key,
    required this.provider,
    required this.contentUrl,
    required this.title,
  });

  final String provider;
  final String contentUrl;
  final String title;

  /// Opens the sheet.
  ///
  /// Returns nothing: the link can be created OR removed here, and the sheet is
  /// also dismissable by dragging, so there is no single result value that is
  /// always right. Callers re-read [AnilistLinkStore] when this completes —
  /// the store is the truth, and it is a synchronous local read.
  static Future<void> show(
    BuildContext context, {
    required String provider,
    required String contentUrl,
    required String title,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => AnilistLinkSheet(
        provider: provider,
        contentUrl: contentUrl,
        title: title,
      ),
    );
  }

  @override
  State<AnilistLinkSheet> createState() => _AnilistLinkSheetState();
}

class _AnilistLinkSheetState extends State<AnilistLinkSheet> {
  final AnilistService _service = getIt<AnilistService>();
  final AnilistLinkStore _store = getIt<AnilistLinkStore>();
  late final TextEditingController _query =
      TextEditingController(text: widget.title);

  Timer? _debounce;

  /// Guards against an earlier, slower search overwriting a later one's results.
  int _token = 0;

  List<AnilistMedia> _results = const [];
  bool _searching = false;
  String? _error;
  AnilistLink? _current;

  @override
  void initState() {
    super.initState();
    _current = _store.get(widget.provider, widget.contentUrl);
    _search(widget.title);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(value));
  }

  Future<void> _search(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
        _error = null;
      });
      return;
    }

    final token = ++_token;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await _service.api.searchMedia(query, perPage: 20);
      if (!mounted || token != _token) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _searching = false;
        _error =
            e is AnilistException ? e.message : 'anilist.browse_failed'.tr();
      });
    }
  }

  Future<void> _link(AnilistMedia media) async {
    await _store.save(
      AnilistLink(
        provider: widget.provider,
        contentUrl: widget.contentUrl,
        mediaId: media.id,
        title: media.displayTitle,
        coverImage: media.coverImage,
        totalEpisodes: media.episodes,
        linkedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    // Push the new association to the account immediately: the TV cannot make
    // one itself, and waiting for the next app start would leave it untracked
    // through a whole evening of viewing.
    unawaited(_service.syncLinks());
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('anilist.linked_to'.tr(args: [media.displayTitle])),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _unlink() async {
    await _store.remove(widget.provider, widget.contentUrl);
    unawaited(_service.syncLinks());
    if (!mounted) return;
    setState(() => _current = null);
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'anilist.link_title'.tr(),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'anilist.link_hint'.tr(),
                      style: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                    if (_current != null) ...[
                      const SizedBox(height: 12),
                      _CurrentLink(link: _current!, onUnlink: _unlink),
                    ],
                    const SizedBox(height: 14),
                    TextField(
                      controller: _query,
                      onChanged: _onQueryChanged,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _search,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14.5,
                      ),
                      decoration: InputDecoration(
                        hintText: 'anilist.link_search_hint'.tr(),
                        hintStyle: const TextStyle(color: AppColors.textHint),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: AppColors.textHint,
                          size: 20,
                        ),
                        suffixIcon: _searching
                            ? const Padding(
                                padding: EdgeInsets.all(13),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: kAnilistBlue,
                                  ),
                                ),
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 13),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildResults(scrollController)),
            ],
          ),
        ),
      ),
    );
  }

  /// Every branch hands the sheet's controller to a scrollable, including the
  /// ones with nothing to scroll: that controller is what drives the drag, and
  /// without it the sheet cannot be resized or flung shut at all.
  Widget _buildResults(ScrollController scrollController) {
    if (_error != null) {
      return AnilistScrollableMessage(
        controller: scrollController,
        message: AnilistStateMessage(
          icon: Icons.cloud_off_rounded,
          text: _error!,
          actionLabel: 'anilist.retry'.tr(),
          onAction: () => _search(_query.text),
        ),
      );
    }
    if (_results.isEmpty) {
      if (_searching) {
        return ListView(
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [],
        );
      }
      return AnilistScrollableMessage(
        controller: scrollController,
        message: AnilistStateMessage(
          icon: Icons.search_off_rounded,
          text: 'anilist.link_no_results'.tr(),
        ),
      );
    }

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 9),
      itemBuilder: (_, i) => _ResultTile(
        media: _results[i],
        selected: _current?.mediaId == _results[i].id,
        onTap: () => _link(_results[i]),
      ),
    );
  }
}

class _CurrentLink extends StatelessWidget {
  const _CurrentLink({required this.link, required this.onUnlink});

  final AnilistLink link;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: kAnilistBlue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: kAnilistBlue.withValues(alpha: 0.3), width: 0.7),
      ),
      child: Row(
        children: [
          const Icon(Icons.link_rounded, color: kAnilistBlue, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              link.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: onUnlink,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              minimumSize: const Size(0, 34),
            ),
            child: Text(
              'anilist.unlink'.tr(),
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.media,
    required this.selected,
    required this.onTap,
  });

  final AnilistMedia media;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (media.format != null) media.format!,
      if (media.seasonYear != null) '${media.seasonYear}',
      if (media.episodes != null)
        'anilist.n_episodes_short'.tr(args: ['${media.episodes}']),
    ].join(' · ');

    return Material(
      color: selected
          ? kAnilistBlue.withValues(alpha: 0.12)
          : Colors.white.withValues(alpha: 0.035),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Row(
            children: [
              AnilistCover(url: media.coverImage, width: 42, radius: 7),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      media.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle_rounded,
                    color: kAnilistBlue, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
