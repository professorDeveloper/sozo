import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/profile_scope.dart';
import 'package:soplay/features/manga/domain/reading/novel_highlight.dart';

/// Highlights, one list per title.
///
/// In the settings box under a profile-scoped key rather than in history:
/// clearing history is a routine thing to do and must not take somebody's
/// notes with it.
///
/// Best-effort like [ChapterReadStore]: the reader keeps working when the box
/// is not open.
class NovelHighlightStore {
  NovelHighlightStore();

  static const String _prefix = 'novel_highlights:';

  Box<dynamic>? get _box {
    try {
      return Hive.box(AppConstants.settingsBox);
    } catch (_) {
      return null;
    }
  }

  static String keyFor(String provider, String contentUrl) {
    final ns = ProfileScope.namespace;
    final base = '$_prefix$provider|$contentUrl';
    return ns == null ? base : '$base@p_$ns';
  }

  /// Every highlight of the title, in reading order.
  List<NovelHighlight> all(String provider, String contentUrl) {
    final raw = _box?.get(keyFor(provider, contentUrl));
    if (raw is! String || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return [for (final item in list) ?NovelHighlight.fromJson(item)]
        ..sort(_readingOrder);
    } catch (_) {
      return [];
    }
  }

  List<NovelHighlight> forChapter(
    String provider,
    String contentUrl, {
    required String ref,
    required int number,
  }) => [
    for (final h in all(provider, contentUrl))
      if (h.belongsTo(ref, number)) h,
  ];

  Future<void> add(String provider, String contentUrl, NovelHighlight h) =>
      _write(provider, contentUrl, (list) => list..add(h));

  /// Replaces the highlight with the same id.
  Future<void> update(String provider, String contentUrl, NovelHighlight h) =>
      _write(provider, contentUrl, (list) {
        final i = list.indexWhere((e) => e.id == h.id);
        if (i >= 0) list[i] = h;
        return list;
      });

  Future<void> remove(String provider, String contentUrl, Set<String> ids) =>
      _write(
        provider,
        contentUrl,
        (list) => list..removeWhere((e) => ids.contains(e.id)),
      );

  Future<void> _write(
    String provider,
    String contentUrl,
    List<NovelHighlight> Function(List<NovelHighlight>) edit,
  ) async {
    final box = _box;
    if (box == null) return;
    final key = keyFor(provider, contentUrl);
    final list = edit(all(provider, contentUrl));
    try {
      if (list.isEmpty) {
        await box.delete(key);
      } else {
        await box.put(key, jsonEncode([for (final h in list) h.toJson()]));
      }
    } catch (e) {
      debugPrint('[highlights] could not write: $e');
    }
  }

  static int _readingOrder(NovelHighlight a, NovelHighlight b) {
    final byChapter = a.chapter.compareTo(b.chapter);
    if (byChapter != 0) return byChapter;
    final byBlock = a.block.compareTo(b.block);
    return byBlock != 0 ? byBlock : a.start.compareTo(b.start);
  }
}
