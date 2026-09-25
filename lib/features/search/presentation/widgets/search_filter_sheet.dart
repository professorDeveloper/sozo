import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';
import 'package:soplay/core/tv/tv.dart';
import 'package:soplay/features/search/domain/entities/genre_entity.dart';

class SearchFilterSelection {
  const SearchFilterSelection({this.genre = ''});

  final String genre;

  bool get hasActiveFilter => genre.isNotEmpty;

  SearchFilterSelection copyWith({String? genre}) {
    return SearchFilterSelection(genre: genre ?? this.genre);
  }
}

class SearchFilterSheet extends StatefulWidget {
  const SearchFilterSheet({
    super.key,
    required this.initialSelection,
    required this.genres,
    required this.onApply,
  });

  final SearchFilterSelection initialSelection;
  final List<GenreEntity> genres;
  final ValueChanged<SearchFilterSelection> onApply;

  @override
  State<SearchFilterSheet> createState() => _SearchFilterSheetState();
}

class _SearchFilterSheetState extends State<SearchFilterSheet> {
  late SearchFilterSelection _selection;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selection = widget.initialSelection;
  }

  /// The chips to draw, narrowed by the filter field.
  ///
  /// The selected genre is pinned first and is never filtered out. Without
  /// that, typing enough to narrow the list removes the chip showing what is
  /// currently on — so the sheet stops saying what it is doing at exactly the
  /// moment somebody is changing it, and the only way to see the current value
  /// again is to clear what they just typed.
  List<SearchFilterOption> get _options {
    final q = _query.trim().toLowerCase();
    bool hit(GenreEntity g) =>
        q.isEmpty ||
        g.name.toLowerCase().contains(q) ||
        g.slug.toLowerCase().contains(q);

    SearchFilterOption of(GenreEntity g) => SearchFilterOption(
      label: g.name.isNotEmpty ? g.name : g.slug,
      value: g.slug,
    );

    final selected = _selection.genre;
    return [
      for (final g in widget.genres)
        if (g.slug == selected) of(g),
      for (final g in widget.genres)
        if (g.slug != selected && hit(g)) of(g),
    ];
  }

  void _clearFilters() {
    setState(() => _selection = const SearchFilterSelection());
  }

  void _applyFilters() {
    widget.onApply(_selection);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF161616).withValues(alpha: 0.96),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          // A Column, not a scroll view.
          //
          // Everything used to be inside one `SingleChildScrollView`: the
          // title, every genre chip, AND the buttons that commit the choice.
          // On a source with forty-one genres that puts Apply below the fold —
          // so you tap a chip, nothing appears to happen, and the control that
          // would have applied it is somewhere off the bottom of a sheet that
          // gave no sign it scrolled. Only the chips scroll now; the commit row
          // is pinned where a thumb already is.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SheetHandle(),
              const SizedBox(height: 20),
              Text(
                'search.filter'.tr(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (widget.genres.isNotEmpty) ...[
                // Past this many, reading the list is slower than typing.
                if (widget.genres.length > 15) ...[
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'search.filter_genres_hint'.tr(),
                      prefixIcon: const Icon(Icons.search_rounded, size: 19),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                // Flexible, not Expanded: a source with six genres still gets
                // a short sheet rather than one stretched to the cap.
                Flexible(
                  child: SingleChildScrollView(
                    child: SearchFilterChipSection(
                      title: 'search.categories'.tr(),
                      options: _options,
                      selectedValue: _selection.genre,
                      onSelected: (genre) {
                        final next = _selection.genre == genre ? '' : genre;
                        setState(
                          () =>
                              _selection = _selection.copyWith(genre: next),
                        );
                        // A chip IS the choice. Making somebody tap it and
                        // then tap Apply is asking them to confirm a decision
                        // they have already expressed — and clearing still
                        // reaches the bloc, which `search_page` documents as
                        // load-bearing when there is text in the box.
                        _applyFilters();
                      },
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _clearFilters,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(kButtonRadius),
                        ),
                      ),
                      child: Text(
                        'search.clear_filter'.tr(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _applyFilters,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(kButtonRadius),
                        ),
                      ),
                      child: Text(
                        'search.apply'.tr(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
                ),
              SizedBox(height: bottomPad + 16),
            ],
          ),
        ),
      ),
    );
  }
}

class SearchFilterOption {
  const SearchFilterOption({required this.label, required this.value});

  final String label;
  final String value;
}

class SearchFilterChipSection extends StatelessWidget {
  const SearchFilterChipSection({
    super.key,
    required this.title,
    required this.options,
    required this.selectedValue,
    required this.onSelected,
  });

  final String title;
  final List<SearchFilterOption> options;
  final String selectedValue;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(title),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options
              .map(
                (option) => _SheetChip(
                  label: option.label,
                  selected: selectedValue == option.value,
                  onTap: () => onSelected(option.value),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: AppColors.textHint,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _SheetChip extends StatelessWidget {
  const _SheetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.18)
            : AppColors.surfaceVariant.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? AppColors.primary : AppColors.textSecondary,
          fontSize: 13,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );

    // Android TV: every option in the filter sheet is one of these chips, so on
    // a bare GestureDetector the sheet opened but nothing in it could be picked.
    if (isTvPlatform) {
      return TvFocusable(onPressed: onTap, borderRadius: 10, child: chip);
    }

    return GestureDetector(onTap: onTap, child: chip);
  }
}
