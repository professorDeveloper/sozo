import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/entities/record_info.dart';

/// What the catalogue knows and a source does not, as its own tab.
///
/// It was a grid under the Play button and filled the page before the tabs
/// were reached; a title's record is worth a tab of its own, and only a
/// title that came with a record gets one. Studio, what it was adapted
/// from, how many episodes, where it ranks, its status — each in its own
/// cell, so the eye can find one without reading the others.
///
/// ## Why the cells are not all the same
///
/// They were: eight identical grey boxes, each an uppercase letter-spaced grey
/// label over a value. Nothing distinguished the studio from the rank from the
/// status, so finding one meant reading all of them, and the tab read as a
/// column of the same card repeated. Two things now carry meaning without
/// inventing any data. Each fact gets the icon of the KIND of thing it is, so
/// it can be found by shape. And status is the one fact with a state rather
/// than a value — airing, finished, cancelled — so it is coloured by that
/// state, which is the whole of what somebody opening this tab wants to know.
class DetailAboutTab extends StatelessWidget {
  const DetailAboutTab({super.key, required this.record});

  final RecordInfo record;

  /// The kind of thing each fact is, as a glyph. Keyed on the label key, which
  /// is the only stable identity a [RecordFact] has — the text is translated
  /// and the value is free-form.
  static const Map<String, IconData> _icons = {
    'detail.about_studio': Icons.apartment_rounded,
    'detail.about_author': Icons.person_rounded,
    'detail.about_source': Icons.menu_book_rounded,
    'detail.about_episodes': Icons.playlist_play_rounded,
    'detail.about_chapters': Icons.article_rounded,
    'detail.about_volumes': Icons.collections_bookmark_rounded,
    'detail.about_seasons': Icons.layers_rounded,
    'detail.about_rank': Icons.emoji_events_rounded,
    'detail.about_status': Icons.circle_rounded,
    'detail.about_format': Icons.live_tv_rounded,
    'detail.about_network': Icons.cell_tower_rounded,
    'detail.about_budget': Icons.payments_rounded,
    'detail.about_collection': Icons.folder_special_rounded,
  };

  /// Status is the one fact that is a STATE, so it is the one that earns a
  /// colour: still going, done, or stopped. Matched on the English words the
  /// catalogues emit, lowercased, because that is what reaches here before the
  /// value is shown — an unrecognised status simply stays neutral.
  static Color? _statusColor(String value) {
    final v = value.toLowerCase();
    if (v.contains('releasing') ||
        v.contains('airing') ||
        v.contains('ongoing') ||
        v.contains('returning')) {
      return const Color(0xFF3FB950);
    }
    if (v.contains('finished') || v.contains('ended') || v.contains('complete')) {
      return const Color(0xFF8B949E);
    }
    if (v.contains('cancelled') || v.contains('canceled') || v.contains('hiatus')) {
      return const Color(0xFFE5484D);
    }
    if (v.contains('not yet') || v.contains('upcoming') || v.contains('planned')) {
      return const Color(0xFFD29922);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cells = [
      for (final f in record.facts) (f.labelKey, f.labelKey.tr(), f.value),
    ];
    if (cells.isEmpty && record.tags.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final columns = c.maxWidth >= 520 ? 3 : 2;
              final width = (c.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final (key, label, value) in cells)
                    SizedBox(
                      width: width,
                      child: _FactCell(
                        icon: _icons[key] ?? Icons.info_rounded,
                        label: label,
                        value: value,
                        // Only the status cell is coloured; everywhere else a
                        // colour would be decoration pretending to be meaning.
                        accent: key == 'detail.about_status'
                            ? _statusColor(value)
                            : null,
                      ),
                    ),
                ],
              );
            },
          ),
          if (record.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in record.tags)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      t,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One fact: what kind of thing it is, what it is called, and what it says.
class _FactCell extends StatelessWidget {
  const _FactCell({
    required this.icon,
    required this.label,
    required this.value,
    this.accent,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Set only for a fact whose value is a state — see [DetailAboutTab].
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 9, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 1, end: 9),
            child: Icon(
              icon,
              // The status dot is small because it IS a dot; every other glyph
              // is a label for its row.
              size: accent != null ? 10 : 16,
              color: accent ?? AppColors.textHint,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent ?? AppColors.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
