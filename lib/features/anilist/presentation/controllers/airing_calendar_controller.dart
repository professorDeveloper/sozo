import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/features/anilist/data/anilist_api.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';
import 'package:soplay/features/sources/domain/source_failure.dart';

/// One row of a day's list.
///
/// Usually one airing. Two airings of the same show in the same minute are how
/// the schedule encodes a double-episode drop, not two events — rendering them
/// as two identical rows differing only in episode number reads as a bug. Two
/// airings at two DIFFERENT times stay two rows, because that is the truth.
class AiringDayRow {
  const AiringDayRow({required this.airing, required this.lastEpisode});

  final AnilistScheduledAiring airing;
  final int lastEpisode;

  int get firstEpisode => airing.episode;
  bool get isRange => lastEpisode > airing.episode;
}

/// The airing window, one day at a time.
///
/// Days are fetched on demand and kept, rather than pulling the window up
/// front: a day of global airings is a hundred-odd entries and most of the
/// window is days the user never looks at. Switching back to a day already
/// seen is then instant.
class AiringCalendarController extends ChangeNotifier {
  AiringCalendarController({required AnilistService service})
    : _service = service,
      _mineOnly = _readMineOnly();

  /// Yesterday earns its pill — "did last night's episode actually drop?" is a
  /// real question. Two weeks forward is roughly as far ahead as AniList
  /// announces. Backwards beyond yesterday is left to the library views.
  static const int _daysBefore = 1;
  static const int _daysAfter = 13;

  /// How long a fetched day is trusted before a re-select refetches it. Today
  /// moves — delays and newly announced episodes land on it — so it is held
  /// far more briefly than a day that is already fixed.
  static const Duration _todayFreshness = Duration(minutes: 10);
  static const Duration _dayFreshness = Duration(hours: 6);

  static const String _mineOnlyKey = 'anilist_calendar_mine_only';

  final AnilistService _service;

  /// Cache and in-flight state are keyed by the day's midnight, so a rebuild
  /// with a fresh DateTime.now() still hits the same entry.
  final Map<DateTime, List<AnilistScheduledAiring>> _byDay = {};
  final Map<DateTime, DateTime> _fetchedAt = {};
  final Map<DateTime, String> _errors = {};
  final Map<DateTime, Future<void>> _inFlight = {};

  /// Media ids on the viewer's own list, used to mark and to filter.
  Set<int> _mine = <int>{};

  bool _mineOnly;

  /// Today as the strip currently draws it. Held rather than recomputed per
  /// build so the strip and the selection can never disagree about which day
  /// is which; [syncToToday] is what moves it.
  DateTime _anchor = startOfDay(DateTime.now());
  late DateTime _selected = _anchor;

  DateTime get selected => _selected;
  DateTime get today => _anchor;
  bool get isConnected => _service.isConnected;

  /// The filter only exists while connected, so a disconnect falls back to All
  /// without discarding the preference a reconnect should restore.
  bool get mineOnly => _mineOnly && _service.isConnected;

  /// The days on offer, anchored to today rather than to the calendar week:
  /// "what's on" is read forward, and a Sunday would otherwise offer six days
  /// that have already happened.
  List<DateTime> get days => List<DateTime>.generate(
    _daysBefore + 1 + _daysAfter,
    (i) => DateTime(_anchor.year, _anchor.month, _anchor.day - _daysBefore + i),
  );

  int get selectedIndex {
    final index = days.indexOf(_selected);
    return index < 0 ? _daysBefore : index;
  }

  bool isMine(int mediaId) => _mine.contains(mediaId);

  /// The day's airings with the filter applied.
  List<AnilistScheduledAiring> airingsFor(DateTime day) {
    final all = _byDay[startOfDay(day)] ?? const <AnilistScheduledAiring>[];
    if (!mineOnly) return all;
    return all.where((a) => _mine.contains(a.media.id)).toList(growable: false);
  }

  List<AiringDayRow> rowsFor(DateTime day) => _collapse(airingsFor(day));

  /// How many airings the day holds under the current filter, or null when the
  /// day has never been fetched — the two are not the same answer, and a strip
  /// marker that conflated them would confidently claim a dozen empty days.
  int? countFor(DateTime day) {
    final all = _byDay[startOfDay(day)];
    if (all == null) return null;
    if (!mineOnly) return all.length;
    return all.where((a) => _mine.contains(a.media.id)).length;
  }

  int totalFor(DateTime day) => (_byDay[startOfDay(day)] ?? const []).length;

  /// Whether the day holds anything at all, regardless of the filter — so the
  /// empty state can say "nothing on your list today" instead of "nothing at
  /// all today", which would be wrong.
  bool hasAnyFor(DateTime day) => totalFor(day) > 0;

  bool loadingFor(DateTime day) => _inFlight.containsKey(startOfDay(day));
  String? errorFor(DateTime day) => _errors[startOfDay(day)];

  /// The day has never resolved — in flight, or not asked for yet, which is
  /// what the page next to the one being swiped away from looks like until
  /// the swipe settles and selects it.
  bool isPendingFor(DateTime day) {
    final key = startOfDay(day);
    return !_byDay.containsKey(key) && !_errors.containsKey(key);
  }

  /// A failed refresh over a day that still holds data. The list keeps showing
  /// what it has, so the failure needs saying somewhere other than the empty
  /// state.
  bool isStaleFor(DateTime day) =>
      errorFor(day) != null && hasAnyFor(day) && !loadingFor(day);

  void select(DateTime day) {
    final normalised = startOfDay(day);
    if (normalised == _selected) return;
    _selected = normalised;
    notifyListeners();
    load();
  }

  void setMineOnly(bool value) {
    if (_mineOnly == value) return;
    _mineOnly = value;
    _persistMineOnly(value);
    notifyListeners();
  }

  /// Records which media the viewer follows, and reports whether that actually
  /// changed — a caller listening to the library as well can then skip the
  /// rebuild this already sent.
  ///
  /// Passed in rather than fetched here: the library screens already hold this
  /// list, and a second copy would drift from theirs after an edit.
  bool setLibrary(Iterable<AnilistListEntry> entries) {
    final ids = entries.map((e) => e.media.id).toSet();
    if (setEquals(ids, _mine)) return false;
    _mine = ids;
    notifyListeners();
    return true;
  }

  /// Re-anchors the window when the clock has crossed midnight.
  ///
  /// Needed on resume above all: an app left backgrounded overnight comes back
  /// with a selection that is no longer on the strip, showing yesterday's
  /// schedule under a strip that starts at today.
  void syncToToday() {
    final now = startOfDay(DateTime.now());
    if (now == _anchor) return;

    final wasOnToday = _selected == _anchor;
    _anchor = now;
    final first = days.first;
    _byDay.removeWhere((day, _) => day.isBefore(first));
    _fetchedAt.removeWhere((day, _) => day.isBefore(first));
    _errors.removeWhere((day, _) => day.isBefore(first));
    if (wasOnToday || _selected.isBefore(first)) _selected = now;
    notifyListeners();
    load();
  }

  Future<void> load({bool force = false}) => loadDay(_selected, force: force);

  Future<void> loadDay(DateTime day, {bool force = false}) {
    final key = startOfDay(day);

    // A forced refresh coalesces onto an in-flight fetch rather than being
    // swallowed by it: pulling to refresh during the first load then holds the
    // indicator until the data actually lands, instead of snapping shut.
    final inFlight = _inFlight[key];
    if (inFlight != null) return inFlight;
    if (!force && _byDay.containsKey(key) && !_isStale(key)) {
      return Future<void>.value();
    }

    final future = _fetch(key);
    _inFlight[key] = future;
    notifyListeners();
    return future;
  }

  Future<void> _fetch(DateTime day) async {
    _errors.remove(day);
    try {
      _byDay[day] = await _service.api.airingSchedule(
        from: day,
        to: DateTime(day.year, day.month, day.day + 1),
      );
      _fetchedAt[day] = DateTime.now();
      _prefetchNext(day);
    } catch (e) {
      // The generic sentence only when nothing more specific is known.
      //
      // AniList's own failures already say what happened; everything else —
      // no connection, a timeout, a 5xx, a response that would not parse —
      // fell into one message that tells the reader nothing and tells a bug
      // report less. [SourceFailure] is the app's existing answer to exactly
      // this and knows the vocabulary of both Dart and Dio, so being offline
      // now says so instead of being reported as the schedule being broken.
      if (e is AnilistException) {
        _errors[day] = e.rateLimited
            ? 'anilist.calendar_rate_limited'.tr()
            : e.message;
      } else {
        final failure = SourceFailure.of(e.toString());
        _errors[day] = failure.kind == SourceFailureKind.unknown
            ? 'anilist.calendar_error'.tr()
            : failure.headline;
      }
    } finally {
      _inFlight.remove(day);
      // The day may no longer be selected — the user can switch while a fetch
      // is in flight — but the result is cached either way, so notifying is
      // still correct: it repaints whichever day they landed on.
      notifyListeners();
    }
  }

  /// Warms tomorrow, and only tomorrow.
  ///
  /// Forward is the direction this list is read, so one day of lookahead takes
  /// the skeleton out of the common swipe. The whole window would be a burst of
  /// thirty-odd requests against a budget AniList enforces tightly, to warm
  /// days most viewers never open.
  void _prefetchNext(DateTime day) {
    if (day != _selected) return;
    final next = DateTime(day.year, day.month, day.day + 1);
    if (next.isAfter(days.last)) return;
    if (_byDay.containsKey(next) || _inFlight.containsKey(next)) return;
    _inFlight[next] = _fetch(next);
  }

  bool _isStale(DateTime day) {
    final at = _fetchedAt[day];
    if (at == null) return true;
    final age = DateTime.now().difference(at);
    return age > (day == _anchor ? _todayFreshness : _dayFreshness);
  }

  /// Collapses same-show, same-minute airings into one row.
  static List<AiringDayRow> _collapse(List<AnilistScheduledAiring> airings) {
    final out = <AiringDayRow>[];
    final at = <String, int>{};
    for (final airing in airings) {
      final key = '${airing.media.id}@${airing.airingAt ~/ 60}';
      final index = at[key];
      if (index == null) {
        at[key] = out.length;
        out.add(AiringDayRow(airing: airing, lastEpisode: airing.episode));
        continue;
      }
      final row = out[index];
      out[index] = AiringDayRow(
        airing: airing.episode < row.airing.episode ? airing : row.airing,
        lastEpisode: airing.episode > row.lastEpisode
            ? airing.episode
            : row.lastEpisode,
      );
    }
    return out;
  }

  /// Built arithmetically rather than by adding a Duration: a day is not always
  /// 24 hours, and on a DST transition `add(Duration(days: 1))` lands at 23:00
  /// or 01:00 — which would key the cache off a time that is not midnight and
  /// hand the query a 23- or 25-hour window.
  static DateTime startOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static bool _readMineOnly() {
    try {
      return Hive.box(
            AppConstants.settingsBox,
          ).get(_mineOnlyKey, defaultValue: false) ==
          true;
    } catch (_) {
      return false;
    }
  }

  static void _persistMineOnly(bool value) {
    try {
      Hive.box(AppConstants.settingsBox).put(_mineOnlyKey, value);
    } catch (_) {
      // Nothing on screen depends on this landing; the filter still works.
    }
  }
}
