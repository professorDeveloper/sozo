import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/item_appear.dart';
import 'package:soplay/features/home/domain/entities/view_all.dart';
import 'package:soplay/features/home/presentation/widgets/view_all_widgets.dart';
import 'package:soplay/features/search/domain/entities/genre_entity.dart';
import 'package:soplay/features/search/presentation/widgets/genre_tile.dart';

/// Every genre the current source lists, as a wall of covers.
///
/// Home shows them as one row that scrolls sideways, which is right for a
/// glance and wrong for choosing: a source with forty genres hides thirty of
/// them past the edge. Here they are all on one screen, and a name can be
/// typed to find one.
///
/// Handed the list Home already has rather than fetching it: the genres are
/// the current source's, Home loaded them with everything else, and asking
/// again would be a second request for the same answer.
class GenresPage extends StatefulWidget {
  const GenresPage({super.key, required this.genres});

  final List<GenreEntity> genres;

  @override
  State<GenresPage> createState() => _GenresPageState();
}

class _GenresPageState extends State<GenresPage> {
  final ScrollController _scroll = ScrollController();
  final ValueNotifier<double> _blur = ValueNotifier<double>(0);
  String _query = '';

  /// Below this a search box is more to look at than there is to search.
  static const int _searchFrom = 12;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients) {
        _blur.value = (_scroll.offset / 80).clamp(0.0, 1.0);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _blur.dispose();
    super.dispose();
  }

  List<GenreEntity> get _shown {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.genres;
    return [
      for (final g in widget.genres)
        if (g.label.toLowerCase().contains(q) ||
            g.slug.toLowerCase().contains(q))
          g,
    ];
  }

  void _open(GenreEntity genre) {
    HapticFeedback.selectionClick();
    context.push(
      '/view-all',
      extra: ViewAllEntity(type: 'genre', slug: genre.slug, name: genre.label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appBarH = MediaQuery.paddingOf(context).top + 56;
    final width = MediaQuery.sizeOf(context).width;
    // Fewer, bigger covers than Search's grid: this page is only genres, so
    // each can be a picture worth recognising rather than a thumbnail — two
    // across a phone, three on a small tablet, four on anything wider.
    final columns = width >= 900 ? 4 : (width >= 600 ? 3 : 2);
    final shown = _shown;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scroll,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: appBarH + 8)),
              if (widget.genres.length >= _searchFrom)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'search.filter_genres_hint'.tr(),
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      ),
                    ),
                  ),
                ),
              if (shown.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        'home.genres_no_match'.tr(),
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      // Wide rather than square: the covers are poster art, and
                      // a band across the middle of one is the recognisable
                      // part; the name sits at the bottom of it.
                      childAspectRatio: 1.62,
                    ),
                    delegate: SliverChildBuilderDelegate((context, i) {
                      final g = shown[i];
                      return ItemAppear(
                        index: i,
                        columns: columns,
                        staggerLimit: 24,
                        child: GenreTile(
                          key: ValueKey(g.slug),
                          label: g.label,
                          image: g.image,
                          index: i,
                          onTap: () => _open(g),
                          labelSize: 15.5,
                        ),
                      );
                    }, childCount: shown.length),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          ),
          ValueListenableBuilder<double>(
            valueListenable: _blur,
            builder: (context, blur, _) =>
                ViewAllAppBar(title: 'home.genres'.tr(), blurProgress: blur),
          ),
        ],
      ),
    );
  }
}
