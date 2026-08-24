import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';
import 'package:soplay/features/mal/data/mal_constants.dart';
import 'package:soplay/features/mal/data/mal_link_store.dart';
import 'package:soplay/features/mal/data/mal_service.dart';
import 'package:soplay/features/mal/domain/entities/mal_entities.dart';
import 'package:soplay/features/mal/presentation/widgets/mal_brand.dart';

/// Ties a local title to a MyAnimeList anime by hand.
///
/// Most MAL links are made automatically, through AniList's `idMal` — so this
/// sheet exists for the cases automation cannot reach: an entry AniList has no
/// MAL counterpart for, and a match that came out wrong. Both are silent
/// failures without a way to see and set the link.
class MalLinkSheet extends StatefulWidget {
  const MalLinkSheet({
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
  /// dismissable by dragging, so no single result value is always right.
  /// Callers re-read [MalLinkStore] when this completes — the store is the
  /// truth, and it is a synchronous local read.
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
      builder: (_) => MalLinkSheet(
        provider: provider,
        contentUrl: contentUrl,
        title: title,
      ),
    );
  }

  @override
  State<MalLinkSheet> createState() => _MalLinkSheetState();
}

class _MalLinkSheetState extends State<MalLinkSheet> {
  final MalService _service = getIt<MalService>();
  final MalLinkStore _store = getIt<MalLinkStore>();
  final TextEditingController _query = TextEditingController();

  List<MalAnime> _results = const [];
  bool _searching = false;
  String? _error;
  Timer? _debounce;

  /// Guards against a slow early search overwriting a fast later one.
  int _token = 0;

  late MalLink? _current = _store.get(widget.provider, widget.contentUrl);

  @override
  void initState() {
    super.initState();
    // Seed with the local title: it is what the user is looking at, and it is
    // right often enough to save them typing.
    _query.text = widget.title;
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
    final token = _service.token;

    if (query.isEmpty || token == null) {
      setState(() {
        _results = const [];
        _searching = false;
        _error = token == null ? 'mal.connect_first'.tr() : null;
      });
      return;
    }

    final ticket = ++_token;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await _service.api.search(query, token: token, limit: 20);
      if (!mounted || ticket != _token) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (e) {
      if (!mounted || ticket != _token) return;
      setState(() {
        _searching = false;
        _error = e is MalException ? e.message : 'mal.search_failed'.tr();
      });
    }
  }

  Future<void> _link(MalAnime anime) async {
    await _store.save(
      MalLink(
        provider: widget.provider,
        contentUrl: widget.contentUrl,
        mediaId: anime.id,
        title: anime.title,
        coverImage: anime.picture,
        totalEpisodes: anime.episodes,
        linkedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    // Push it to the account immediately: the TV cannot make a link itself, and
    // waiting for the next app start would leave it untracked through a whole
    // evening of viewing.
    unawaited(_service.syncLinks());
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('mal.linked_to'.tr(args: [anime.title])),
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
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
              child: Row(
                children: [
                  const MalLogo(size: 22, radius: 6),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'mal.link_title'.tr(),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'mal.link_hint'.tr(),
                          style: const TextStyle(
                            color: AppColors.textHint,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_current != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                child: _CurrentLink(link: _current!, onUnlink: _unlink),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              child: TextField(
                controller: _query,
                onChanged: _onQueryChanged,
                onSubmitted: _search,
                textInputAction: TextInputAction.search,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'anilist.link_search_hint'.tr(),
                  hintStyle: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 14,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppColors.textHint,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: AppColors.surfaceVariant,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(11),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(child: _buildResults(scrollController)),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(ScrollController scrollController) {
    if (_searching && _results.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: kMalBlue),
      );
    }
    if (_error != null) {
      return AnilistScrollableMessage(
        controller: scrollController,
        message: AnilistStateMessage(
          icon: Icons.cloud_off_rounded,
          text: _error!,
          accent: kMalBlue,
        ),
      );
    }
    if (_results.isEmpty) {
      return AnilistScrollableMessage(
        controller: scrollController,
        message: AnilistStateMessage(
          icon: Icons.search_off_rounded,
          text: 'anilist.link_no_results'.tr(),
          accent: kMalBlue,
        ),
      );
    }
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _ResultTile(
        anime: _results[i],
        selected: _current?.mediaId == _results[i].id,
        onTap: () => _link(_results[i]),
      ),
    );
  }
}

class _CurrentLink extends StatelessWidget {
  const _CurrentLink({required this.link, required this.onUnlink});

  final MalLink link;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kMalBlue.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          AnilistCover(url: link.coverImage, width: 38, radius: 7),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'anilist.linked_to'.tr(args: [link.title]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                if (link.auto) ...[
                  const SizedBox(height: 5),
                  AnilistChip(
                    label: 'anilist.auto_matched'.tr(),
                    icon: Icons.auto_fix_high_rounded,
                    color: kMalBlue,
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'anilist.unlink'.tr(),
            onPressed: onUnlink,
            icon: const Icon(
              Icons.link_off_rounded,
              color: AppColors.textHint,
              size: 19,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.anime,
    required this.selected,
    required this.onTap,
  });

  final MalAnime anime;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? kMalBlue.withValues(alpha: 0.12) : AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Row(
            children: [
              AnilistCover(url: anime.picture, width: 40, radius: 7),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      anime.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    if (anime.episodes != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'anilist.n_episodes_short'.tr(args: ['${anime.episodes}']),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.add_link_rounded,
                color: selected ? kMalBlue : AppColors.textHint,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
