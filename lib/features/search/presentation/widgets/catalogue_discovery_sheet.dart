import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
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
  Widget field(String key, Map<String, String> options, {String? fallback}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: DropdownButtonFormField<String>(
          key: ValueKey('$key:${values[key]}'),
          initialValue: options.containsKey(values[key])
              ? values[key]
              : fallback ?? '',
          isExpanded: true,
          menuMaxHeight: math.min(320, MediaQuery.sizeOf(context).height * .4),
          borderRadius: BorderRadius.circular(16),
          dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
          elevation: 3,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
          decoration: InputDecoration(
            labelText: t(key),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          items: options.entries
              .map(
                (e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(
                    e.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => set(key, v ?? ''),
        ),
      );
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
                          field('type', {
                            'movie': t('movie'),
                            'tv': t('tv'),
                          }, fallback: 'movie'),
                        field('sort', {
                          'popular': t('popular'),
                          'rating': t('highest'),
                          'newest': t('newest'),
                          if (!tmdb) 'trending': t('trending'),
                        }, fallback: 'popular'),
                        Text(t('rating'), style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final score in ['', '6', '7', '8', '9'])
                              ChoiceChip(
                                label: Text(
                                  score.isEmpty ? t('any') : '★ $score+',
                                ),
                                selected: (values['rating'] ?? '') == score,
                                onSelected: (_) => set('rating', score),
                              ),
                          ],
                        ),
                        if (tmdb)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              t('votes'),
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        const SizedBox(height: 20),
                        field('year', {
                          '': t('any'),
                          for (int y = year + 1; y >= 1900; y--) '$y': '$y',
                        }),
                        // The TMDB movie genre set is not the television genre set.
                        if (loadingGenres)
                          const LinearProgressIndicator()
                        else if (genresFailed)
                          TextButton(
                            onPressed: loadGenres,
                            child: Text('search.retry'.tr()),
                          )
                        else
                          field('genre', {
                            '': t('any'),
                            for (final g in genres) g.slug: g.name,
                          }),
                        if (!tmdb) ...[
                          field('status', {
                            '': t('any'),
                            'RELEASING': t('releasing'),
                            'FINISHED': t('finished'),
                            'NOT_YET_RELEASED': t('upcoming'),
                            'HIATUS': t('hiatus'),
                            'CANCELLED': t('cancelled'),
                          }),
                          if (widget.kind != 'anilist-novel')
                            field('format', {
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
                          if (widget.kind == 'anilist')
                            field('season', {
                              '': t('any'),
                              'WINTER': t('winter'),
                              'SPRING': t('spring'),
                              'SUMMER': t('summer'),
                              'FALL': t('fall'),
                            }),
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
