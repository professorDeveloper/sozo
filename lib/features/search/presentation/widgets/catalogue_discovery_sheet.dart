import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/search/domain/entities/genre_entity.dart';

/// Server-side discovery. Title search remains a separate, explicit operation.
class CatalogueDiscoverySheet extends StatefulWidget {
  const CatalogueDiscoverySheet({
    super.key,
    required this.kind,
    required this.genres,
    required this.initial,
    required this.onApply,
    required this.loadGenres,
  });
  final Future<Result<List<GenreEntity>>> Function(String type) loadGenres;
  final String kind;
  final List<GenreEntity> genres;
  final Map<String, String> initial;
  final ValueChanged<Map<String, String>> onApply;
  @override
  State<CatalogueDiscoverySheet> createState() =>
      _CatalogueDiscoverySheetState();
}

class _CatalogueDiscoverySheetState extends State<CatalogueDiscoverySheet> {
  late Map<String, String> values = Map.of(widget.initial);
  late List<GenreEntity> genres = widget.genres;
  bool loadingGenres = false;
  bool genresFailed = false;
  int genreRequest = 0;
  @override
  void initState() {
    super.initState();
    if (tmdb) loadGenres();
  }

  Future<void> loadGenres() async {
    final request = ++genreRequest;
    setState(() {
      loadingGenres = true;
      genresFailed = false;
      genres = [];
    });
    final result = await widget.loadGenres(values['type'] ?? 'movie');
    if (!mounted || request != genreRequest) return;
    setState(() {
      loadingGenres = false;
      genresFailed = result.isError;
      genres = result.getOrNull() ?? [];
    });
  }

  bool get tmdb => widget.kind == 'tmdb';
  String t(String key) => 'search.discovery.$key'.tr();
  void set(String key, String value) => setState(() {
    if (value.isEmpty) {
      values.remove(key);
    } else {
      values[key] = value;
    }
    if (key == 'type') {
      values.remove('genre');
      loadGenres();
    }
  });

  /// A labelled group of the controls under it.
  Widget section(String label, Widget child, {IconData? icon}) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );

  /// Every option on screen at once, one tap to choose.
  ///
  /// These were dropdowns, which hide the choices behind a tap and then show
  /// them in a menu that covers the sheet — six of them stacked was six
  /// round trips to learn what could be picked. The option sets are short, so
  /// they are simply laid out.
  Widget choices(
    String key,
    Map<String, String> options, {
    String fallback = '',
    Map<String, IconData> icons = const {},
  }) {
    final current = options.containsKey(values[key]) ? values[key]! : fallback;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in options.entries)
          ChoiceChip(
            showCheckmark: false,
            avatar: icons[e.key] == null ? null : Icon(icons[e.key], size: 16),
            label: Text(e.value),
            selected: current == e.key,
            onSelected: (_) {
              HapticFeedback.selectionClick();
              set(key, e.key);
            },
          ),
      ],
    );
  }

  /// This year and the three before it as chips, anything else from a year
  /// grid. A dropdown of 127 years was the worst control on the sheet: the
  /// year people want is almost always a recent one.
  Widget yearPicker(int year) {
    final quick = [for (var y = year; y > year - 4; y--) '$y'];
    final current = values['year'] ?? '';
    final other = current.isNotEmpty && !quick.contains(current);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          showCheckmark: false,
          label: Text(t('any')),
          selected: current.isEmpty,
          onSelected: (_) => set('year', ''),
        ),
        for (final y in quick)
          ChoiceChip(
            showCheckmark: false,
            label: Text(y),
            selected: current == y,
            onSelected: (_) {
              HapticFeedback.selectionClick();
              set('year', y);
            },
          ),
        ChoiceChip(
          showCheckmark: false,
          avatar: const Icon(Icons.calendar_month_rounded, size: 16),
          label: Text(other ? current : t('other_year')),
          selected: other,
          onSelected: (_) => pickYear(year),
        ),
      ],
    );
  }

  Future<void> pickYear(int year) async {
    final initial = int.tryParse(values['year'] ?? '') ?? year - 10;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('year')),
        contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
        content: SizedBox(
          width: 320,
          height: 340,
          child: YearPicker(
            firstDate: DateTime(1900),
            lastDate: DateTime(year + 1),
            selectedDate: DateTime(initial),
            onChanged: (d) => Navigator.pop(ctx, d.year),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('general.cancel'.tr()),
          ),
        ],
      ),
    );
    if (picked != null && mounted) set('year', '$picked');
  }

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight:
            (MediaQuery.sizeOf(context).height -
                MediaQuery.viewInsetsOf(context).bottom) *
            .82,
      ),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${tmdb ? 'TMDB' : 'AniList'} · ${t('title')}',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(t('hint'), style: theme.textTheme.bodySmall),
                const SizedBox(height: 20),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (tmdb)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 22),
                            child: SizedBox(
                              width: double.infinity,
                              child: SegmentedButton<String>(
                                showSelectedIcon: false,
                                segments: [
                                  ButtonSegment(
                                    value: 'movie',
                                    icon: const Icon(Icons.movie_outlined),
                                    label: Text(t('movie')),
                                  ),
                                  ButtonSegment(
                                    value: 'tv',
                                    icon: const Icon(Icons.tv_rounded),
                                    label: Text(t('tv')),
                                  ),
                                ],
                                selected: {values['type'] ?? 'movie'},
                                onSelectionChanged: (s) {
                                  HapticFeedback.selectionClick();
                                  set('type', s.first);
                                },
                              ),
                            ),
                          ),
                        section(
                          t('sort'),
                          icon: Icons.sort_rounded,
                          choices(
                            'sort',
                            {
                              'popular': t('popular'),
                              'rating': t('highest'),
                              'newest': t('newest'),
                              if (!tmdb) 'trending': t('trending'),
                            },
                            fallback: 'popular',
                            icons: const {
                              'popular': Icons.local_fire_department_rounded,
                              'rating': Icons.star_rounded,
                              'newest': Icons.new_releases_outlined,
                              'trending': Icons.trending_up_rounded,
                            },
                          ),
                        ),
                        section(
                          t('min_rating'),
                          icon: Icons.star_half_rounded,
                          RatingFilter(
                            value: int.tryParse(values['rating'] ?? '') ?? 0,
                            onChanged: (v) => set('rating', v == 0 ? '' : '$v'),
                            note: tmdb ? t('votes') : null,
                          ),
                        ),
                        section(
                          t('year'),
                          icon: Icons.event_rounded,
                          yearPicker(year),
                        ),
                        // The TMDB movie genre set is not the television one.
                        section(
                          t('genre'),
                          icon: Icons.category_outlined,
                          loadingGenres
                              ? const LinearProgressIndicator()
                              : genresFailed
                              ? TextButton.icon(
                                  onPressed: loadGenres,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: Text('general.retry'.tr()),
                                )
                              : choices('genre', {
                                  '': t('any'),
                                  for (final g in genres) g.slug: g.name,
                                }),
                        ),
                        if (!tmdb) ...[
                          section(
                            t('status'),
                            icon: Icons.radio_button_checked_rounded,
                            choices('status', {
                              '': t('any'),
                              'RELEASING': t('releasing'),
                              'FINISHED': t('finished'),
                              'NOT_YET_RELEASED': t('upcoming'),
                              'HIATUS': t('hiatus'),
                              'CANCELLED': t('cancelled'),
                            }),
                          ),
                          if (widget.kind != 'anilist-novel')
                            section(
                              t('format'),
                              icon: Icons.view_module_outlined,
                              choices('format', {
                                '': t('any'),
                                if (widget.kind == 'anilist') ...{
                                  'TV': t('tv'),
                                  'MOVIE': t('movie'),
                                  'OVA': 'OVA',
                                  'ONA': 'ONA',
                                  'SPECIAL': t('special'),
                                  'MUSIC': t('music'),
                                } else ...{
                                  'MANGA': 'Manga',
                                  'ONE_SHOT': 'One-shot',
                                },
                              }),
                            ),
                          if (widget.kind == 'anilist')
                            section(
                              t('season'),
                              icon: Icons.wb_sunny_outlined,
                              choices(
                                'season',
                                {
                                  '': t('any'),
                                  'WINTER': t('winter'),
                                  'SPRING': t('spring'),
                                  'SUMMER': t('summer'),
                                  'FALL': t('fall'),
                                },
                                icons: const {
                                  'WINTER': Icons.ac_unit_rounded,
                                  'SPRING': Icons.local_florist_outlined,
                                  'SUMMER': Icons.wb_sunny_outlined,
                                  'FALL': Icons.eco_outlined,
                                },
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(() => values.clear());
                        if (tmdb) loadGenres();
                      },
                      child: Text('search.clear_filter'.tr()),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          widget.onApply({
                            'sort': 'popular',
                            if (tmdb) 'type': 'movie',
                            ...values,
                          });
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.travel_explore),
                        label: Text(t('show')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Minimum score, as a slider over the ten-point scale films are rated on.
///
/// Chips for 6, 7, 8 and 9 said nothing about what those numbers mean, and
/// left no way to ask for "anything decent" below 6. The slider reads out the
/// score as it moves, says in words what it amounts to, and takes the colour
/// critics' scores are usually drawn in — red to green — so where it sits is
/// legible at a glance.
class RatingFilter extends StatelessWidget {
  const RatingFilter({
    super.key,
    required this.value,
    required this.onChanged,
    this.note,
  });

  /// 0 is "any"; otherwise the minimum score out of 10.
  final int value;
  final ValueChanged<int> onChanged;
  final String? note;

  static Color colorFor(int v, ColorScheme scheme) {
    if (v == 0) return scheme.outline;
    if (v < 5) return const Color(0xFFE5533D);
    if (v < 6) return const Color(0xFFF08A24);
    if (v < 7) return const Color(0xFFF5C518);
    if (v < 8) return const Color(0xFF9CCC4A);
    return const Color(0xFF3FB950);
  }

  static String describe(int v) {
    final key = switch (v) {
      0 => 'any_rating',
      < 5 => 'r_low',
      5 => 'r5',
      6 => 'r6',
      7 => 'r7',
      8 => 'r8',
      _ => 'r9',
    };
    return 'search.discovery.$key'.tr();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = colorFor(value, theme.colorScheme);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: value == 0 ? 0.12 : 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded, size: 18, color: color),
                    const SizedBox(width: 4),
                    Text(
                      value == 0 ? '—' : '$value.0+',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: value == 0 ? theme.colorScheme.outline : color,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  describe(value),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              activeTrackColor: color,
              inactiveTrackColor: theme.colorScheme.surfaceContainerHighest,
              thumbColor: color,
              overlayColor: color.withValues(alpha: 0.14),
              activeTickMarkColor: Colors.white.withValues(alpha: 0.5),
              inactiveTickMarkColor: theme.colorScheme.outlineVariant,
              valueIndicatorColor: color,
              showValueIndicator: ShowValueIndicator.onDrag,
            ),
            child: Slider(
              value: value.toDouble(),
              max: 9,
              divisions: 9,
              label: value == 0 ? describe(0) : '★ $value+',
              semanticFormatterCallback: (v) => describe(v.round()),
              onChanged: (v) {
                if (v.round() == value) return;
                HapticFeedback.selectionClick();
                onChanged(v.round());
              },
            ),
          ),
          Padding(
            // One label per stop, inset by the slider's own padding so each
            // sits under the position it names.
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var tick = 0; tick <= 9; tick++)
                  Text(
                    tick == 0 ? '·' : '$tick',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 6),
            Text(note!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
