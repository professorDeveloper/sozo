import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/torrent/torrent_status.dart';

/// Lets the user pick which video inside a torrent to play.
///
/// ## Why this exists
///
/// Season packs are the normal case on Nyaa, not an edge case — `(01-12)`
/// batches routinely have more seeders than the individual episodes. CloudStream
/// has no picker: `streamUrl()` takes `fileStats.first { path not blank }`, so a
/// 12-episode pack always opens episode 1, and there is no way from the UI to
/// reach episode 7. That is the single biggest gap in their implementation and
/// it is cheap to close — the server already returns the whole file list.
///
/// Files are ordered by the natural number in their name rather than by the
/// order the torrent lists them, because torrents are not reliably sorted and
/// "Episode 10" sorting before "Episode 2" is exactly the kind of small wrong
/// thing that makes a feature feel unfinished.
class TorrentFilePickerSheet extends StatelessWidget {
  const TorrentFilePickerSheet({super.key, required this.files});

  final List<TorrentFileEntry> files;

  /// Shows the picker and resolves to the chosen file, or null if dismissed.
  static Future<TorrentFileEntry?> show(
    BuildContext context,
    List<TorrentFileEntry> files,
  ) {
    return showModalBottomSheet<TorrentFileEntry>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => TorrentFilePickerSheet(files: files),
    );
  }

  /// Sorts `Episode 2` before `Episode 10`.
  ///
  /// Plain string comparison gets this wrong for every zero-padded-inconsistent
  /// release, which is most of them. Comparing digit runs numerically and
  /// everything else lexically is the standard fix.
  @visibleForTesting
  static int naturalCompare(String a, String b) {
    final chunks = RegExp(r'(\d+)|(\D+)');
    final left = chunks.allMatches(a.toLowerCase()).toList();
    final right = chunks.allMatches(b.toLowerCase()).toList();

    for (var i = 0; i < left.length && i < right.length; i++) {
      final l = left[i].group(0)!;
      final r = right[i].group(0)!;
      final ln = int.tryParse(l);
      final rn = int.tryParse(r);
      final comparison =
          (ln != null && rn != null) ? ln.compareTo(rn) : l.compareTo(r);
      if (comparison != 0) return comparison;
    }
    return left.length.compareTo(right.length);
  }

  static String _size(int bytes) {
    if (bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 100 || unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...files]..sort((a, b) => naturalCompare(a.path, b.path));
    final maxHeight = MediaQuery.of(context).size.height * 0.75;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
            child: Text(
              'torrent.pick_file'.tr(),
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'torrent.pick_file_hint'.tr(args: ['${sorted.length}']),
              style: TextStyle(color: AppColors.textHint, fontSize: 13),
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 12,
              ),
              itemCount: sorted.length,
              separatorBuilder: (_, _) =>
                  Divider(color: AppColors.divider, height: 1, indent: 56),
              itemBuilder: (context, index) {
                final file = sorted[index];
                return ListTile(
                  onTap: () => Navigator.of(context).pop(file),
                  leading: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    _size(file.lengthBytes),
                    style: TextStyle(color: AppColors.textHint, fontSize: 12),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
