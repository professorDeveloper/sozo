import 'package:soplay/features/search/presentation/pages/cross_search_page.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_state.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';
import 'package:soplay/features/anilist/data/anilist_api.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_logo.dart';

/// What the seasons of a year are called, and which one a month falls in.
({String season, int year}) _currentSeason([DateTime? at]) {
  final now = at ?? DateTime.now();
  final season = switch (now.month) {
    12 || 1 || 2 => 'WINTER',
    3 || 4 || 5 => 'SPRING',
    6 || 7 || 8 => 'SUMMER',
    _ => 'FALL',
  };
  // December belongs to the winter season of the NEXT year, which is how
  // AniList files it — asking for WINTER of this year in December returns the
  // season that ended eleven months ago.
  final year = now.month == 12 ? now.year + 1 : now.year;
  return (season: season, year: year);
}

enum _Shelf { trending, season, popular, upcoming }

/// Discovery on AniList.
///
/// The library only ever showed your own list, so there was nothing in the app
/// that answered "what should I watch". This is that half — and it ends in
/// "find it in sources", because discovering something you then cannot open is
/// a dead end.
class AnilistBrowsePage extends StatefulWidget {
  const AnilistBrowsePage({super.key});

  @override
  State<AnilistBrowsePage> createState() => _AnilistBrowsePageState();
}

class _AnilistBrowsePageState extends State<AnilistBrowsePage> {
  final AnilistService _service = getIt<AnilistService>();

  _Shelf _shelf = _Shelf.trending;
  final Map<_Shelf, List<AnilistMedia>> _cache = {};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(_shelf);
  }

  /// Loads one shelf.
  ///
  /// Every state write is guarded on the shelf still being the selected one:
  /// switching tabs while a fetch is in flight used to let the old answer clear
  /// the spinner over the new tab and declare it empty.
  Future<void> _load(_Shelf shelf, {bool force = false}) async {
    if (!force && _cache.containsKey(shelf)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final season = _currentSeason();
      final media = await _service.api.browse(
        sort: switch (shelf) {
          _Shelf.trending => 'TRENDING_DESC',
          _Shelf.popular => 'POPULARITY_DESC',
          _Shelf.season => 'POPULARITY_DESC',
          _Shelf.upcoming => 'POPULARITY_DESC',
        },
        season: shelf == _Shelf.season ? season.season : null,
        seasonYear: shelf == _Shelf.season ? season.year : null,
        status: shelf == _Shelf.upcoming ? 'NOT_YET_RELEASED' : null,
      );
      if (!mounted) return;
      setState(() {
        _cache[shelf] = media;
        if (shelf == _shelf) _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (shelf != _shelf) return;
      final message =
          e is AnilistException ? e.message : 'anilist.browse_failed'.tr();
      setState(() {
        _loading = false;
        _error = message;
      });
      // A failed refresh over a shelf that still holds titles has nowhere else
      // to show: the grid keeps rendering what it has.
      if (_cache[shelf]?.isNotEmpty ?? false) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  String _label(_Shelf shelf) => switch (shelf) {
    _Shelf.trending => 'anilist.browse_trending'.tr(),
    _Shelf.season => 'anilist.browse_season'.tr(),
    _Shelf.popular => 'anilist.browse_popular'.tr(),
    _Shelf.upcoming => 'anilist.browse_upcoming'.tr(),
  };

  @override
  Widget build(BuildContext context) {
    final items = _cache[_shelf] ?? const <AnilistMedia>[];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Row(
          children: [
            const AnilistLogo(size: 20),
            const SizedBox(width: 9),
            Text(
              'anilist.browse_title'.tr(),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: _Shelf.values.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final shelf = _Shelf.values[i];
                  final active = shelf == _shelf;
                  return Material(
                    color: active
                        ? kAnilistBlue.withValues(alpha: 0.16)
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        if (shelf == _shelf) return;
                        setState(() {
                          _shelf = shelf;
                          _error = null;
                          _loading = false;
                        });
                        _load(shelf);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: active ? kAnilistBlue : Colors.transparent,
                            width: 1.2,
                          ),
                        ),
                        child: Text(
                          _label(shelf),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: active
                                ? kAnilistBlue
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Expanded(child: _body(items)),
          ],
        ),
      ),
    );
  }

  Widget _body(List<AnilistMedia> items) {
    if (_loading && items.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: kAnilistBlue, strokeWidth: 2.5),
      );
    }
    if (_error != null && items.isEmpty) {
      return AnilistScrollableMessage(
        message: AnilistStateMessage(
          icon: Icons.cloud_off_rounded,
          text: _error!,
          actionLabel: 'anilist.retry'.tr(),
          onAction: () => _load(_shelf, force: true),
        ),
      );
    }
    if (items.isEmpty) {
      return AnilistScrollableMessage(
        message: AnilistStateMessage(
          icon: Icons.explore_off_rounded,
          text: 'anilist.browse_empty'.tr(),
        ),
      );
    }

    const gutter = 14.0;
    const spacing = 10.0;
    const gap = 6.0;
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 6 : (width >= 620 ? 5 : 3);
    final cell = (width - gutter * 2 - spacing * (columns - 1)) / columns;
    final caption = _MediaCard.reserveCaption(context);

    return RefreshIndicator(
      color: kAnilistBlue,
      backgroundColor: AppColors.surface,
      onRefresh: () => _load(_shelf, force: true),
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(gutter, 12, gutter, 28),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 12,
          crossAxisSpacing: spacing,
          // A 2:3 poster plus exactly two lines of caption. The old fixed
          // ratio made the cell taller than that, and the cover stretched to
          // fill it — the one thing AnilistCover exists to prevent.
          childAspectRatio: cell / (cell * 3 / 2 + gap + caption),
        ),
        itemCount: items.length,
        itemBuilder: (context, i) => _MediaCard(
          media: items[i],
          captionHeight: caption,
          onTap: () => _openSheet(items[i]),
        ),
      ),
    );
  }

  void _openSheet(AnilistMedia media) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _MediaSheet(media: media),
    );
  }
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({
    required this.media,
    required this.captionHeight,
    required this.onTap,
  });

  static const double _fontSize = 11.5;
  static const double _lineHeight = 1.2;

  /// Two lines, always — a one-line title would otherwise let its poster grow
  /// taller than its neighbours' and break the row.
  static double reserveCaption(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(_fontSize) * _lineHeight * 2;

  final AnilistMedia media;
  final double captionHeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title =
        media.englishTitle ?? media.romajiTitle ?? media.nativeTitle ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnilistCover(url: media.coverImage, radius: 10),
                ),
                if (media.averageScore != null)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${media.averageScore}%',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: captionHeight,
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: _fontSize,
                height: _lineHeight,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What one title is, and the one thing worth doing about it.
class _MediaSheet extends StatelessWidget {
  const _MediaSheet({required this.media});

  final AnilistMedia media;

  @override
  Widget build(BuildContext context) {
    final title =
        media.englishTitle ?? media.romajiTitle ?? media.nativeTitle ?? '';
    final description = (media.description ?? '')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .trim();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      maxChildSize: 0.92,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnilistCover(url: media.coverImage, width: 92, radius: 10),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (media.format != null) AnilistChip(label: media.format!),
                        if (media.seasonYear != null)
                          AnilistChip(label: '${media.seasonYear}'),
                        if (media.episodes != null)
                          AnilistChip(
                            label: 'anilist.episodes_count'.tr(
                              namedArgs: {'count': '${media.episodes}'},
                            ),
                          ),
                        if (media.averageScore != null)
                          AnilistChip(label: '${media.averageScore}%'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          // The bridge. Discovering something you cannot then open is a dead
          // end, and the source apps know nothing about AniList ids — the title
          // is what crosses.
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.push('/cross-search', extra: title);
                    },
                    icon: const Icon(Icons.travel_explore_rounded, size: 19),
                    label: Text('anilist.find_in_sources'.tr()),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Searching every installed source buries the answer when you
              // already know which one carries this. The caret narrows it to one.
              SizedBox(
                height: 46,
                width: 46,
                child: OutlinedButton(
                  onPressed: () => _pickSource(context, title),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(kButtonRadius),
                    ),
                  ),
                  child: const Icon(Icons.expand_more_rounded, size: 20),
                ),
              ),
            ],
          ),

          if (description.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              description,
              style: const TextStyle(
                fontSize: 13,
                height: 1.55,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}


/// Lets the caller name the source before the search runs.
///
/// The provider list comes from the same bloc the search screens read, so a
/// source the user has not installed is never offered.
Future<void> _pickSource(BuildContext context, String title) async {
  final state = context.read<ProviderBloc>().state;
  final providers = state is ProviderLoaded
      ? state.usableProviders
      : const <ProviderEntity>[];

  if (providers.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('anilist.no_sources'.tr()),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  final picked = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'anilist.search_in_source'.tr(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: AppColors.textHint,
                ),
              ),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: providers.length,
              itemBuilder: (_, i) => ListTile(
                leading: const Icon(
                  Icons.dns_outlined,
                  color: AppColors.textSecondary,
                ),
                title: Text(providers[i].name),
                onTap: () => Navigator.of(sheetContext).pop(providers[i].id),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (picked == null || !context.mounted) return;
  Navigator.of(context).pop();
  context.push(
    '/cross-search',
    extra: CrossSearchRequest(query: title, providerIds: {picked}),
  );
}
