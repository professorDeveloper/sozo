import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/profile_scope.dart';

/// Which chapters of a title have been read.
///
/// The app knew whether a chapter had been REPORTED to a tracker this session
/// (`ChapterProgress`) and where the reader had got to in the one chapter it
/// was last in (history), and neither survives as "I have read this". So a
/// chapter list of four hundred rows looked identical whether you had read one
/// of them or three hundred — the single most useful thing a reader can be told
/// about a list, and it was not there.
///
/// Append-only except for an explicit unmark. Reading on past a chapter, going
/// back to re-read it, closing and reopening it, switching source, and the
/// tracker ledger being cleared at the end of a session all leave the mark
/// exactly where it was: the only two things that remove one are the reader
/// asking to, and the title's whole record being cleared.
///
/// Chapter NUMBERS rather than indices or refs. An index moves the moment a
/// source inserts an extra, and a ref changes when a source moves domain or
/// re-keys its chapters — either of which would silently un-read a whole
/// library. The number is the one identity a chapter keeps, and it is what a
/// tracker is told as well, so the two agree by construction.
///
/// Every operation is best-effort. The reader has to keep working when the box
/// is unavailable, which is every widget test and the moment before Hive opens.
class ChapterReadStore {
  ChapterReadStore();

  static const String _prefix = 'chapters_read:';

  Box<dynamic>? get _box {
    try {
      return Hive.box(ProfileScope.box(AppConstants.historyBox));
    } catch (_) {
      return null;
    }
  }

  /// One title, identified by the source it is read on and its url there.
  ///
  /// Both halves matter: the same work on two sources is two chapter lists that
  /// rarely agree on numbering, and merging them would mark chapters read that
  /// nobody opened.
  static String keyFor(String provider, String contentUrl) =>
      '$_prefix$provider|$contentUrl';

  /// The chapter numbers marked read, or an empty set.
  Set<int> read(String provider, String contentUrl) {
    final raw = _box?.get(keyFor(provider, contentUrl));
    if (raw is! List) return <int>{};
    return {
      for (final v in raw)
        if (v is int) v else if (v is num) v.toInt(),
    };
  }

  bool isRead(String provider, String contentUrl, int chapter) =>
      read(provider, contentUrl).contains(chapter);

  /// Marks [chapters] read. Numbers at or below zero are ignored.
  ///
  /// A source numbers extras, omakes and announcements 0 or less, and a mark on
  /// one of those is a mark the reader cannot see or undo — the same rule the
  /// tracker ledger applies, for the same reason.
  Future<void> mark(
    String provider,
    String contentUrl,
    Iterable<int> chapters,
  ) => _write(provider, contentUrl, (current) {
    var changed = false;
    for (final c in chapters) {
      if (c > 0 && current.add(c)) changed = true;
    }
    return changed;
  });

  Future<void> unmark(
    String provider,
    String contentUrl,
    Iterable<int> chapters,
  ) => _write(provider, contentUrl, (current) {
    var changed = false;
    for (final c in chapters) {
      if (current.remove(c)) changed = true;
    }
    return changed;
  });

  /// Forgets everything known about one title.
  Future<void> clear(String provider, String contentUrl) async {
    try {
      await _box?.delete(keyFor(provider, contentUrl));
    } catch (_) {}
  }

  /// Applies [edit] to the stored set and writes it back only if it said
  /// something changed.
  ///
  /// The guard is not an optimisation. The reader marks the current chapter on
  /// every position update once it is past the threshold, which is several
  /// times a second on a scroll — writing an identical list each time would put
  /// a Hive flush on the scroll path for no change at all.
  Future<void> _write(
    String provider,
    String contentUrl,
    bool Function(Set<int> current) edit,
  ) async {
    final box = _box;
    if (box == null) return;
    final key = keyFor(provider, contentUrl);
    final current = read(provider, contentUrl);
    if (!edit(current)) return;
    final sorted = current.toList()..sort();
    try {
      if (sorted.isEmpty) {
        await box.delete(key);
      } else {
        await box.put(key, sorted);
      }
    } catch (e) {
      debugPrint('[chapters] could not write read state: $e');
    }
  }
}
