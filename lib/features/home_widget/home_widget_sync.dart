import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:soplay/core/router/app_router.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/features/achievements/domain/achievements.dart';
import 'package:soplay/features/achievements/presentation/widgets/achievement_medal.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/streak/data/streak_service.dart';
import 'package:soplay/features/profiles/data/profile_session.dart';
import 'package:soplay/features/profiles/domain/household_profile.dart';
import 'package:soplay/features/profiles/presentation/widgets/profile_avatar.dart';
import 'package:soplay/core/content/content_mode.dart';

/// Keeps the Android home screen widgets in step with the app.
///
/// The widgets draw a snapshot and nothing else, so everything they show is
/// decided here: the three titles Home would offer to continue, in the
/// viewer's language; their posters, fetched and shrunk to files the widget
/// can read; the streak; and the next episode due from the viewer's AniList
/// list. Anything that changes with the clock — the countdown, whether the
/// streak is at risk tonight — is left to the widget, which redraws without
/// the app.
class HomeWidgetSync with WidgetsBindingObserver {
  HomeWidgetSync({
    required HistoryService history,
    required StreakService streak,
    required HiveService hive,
    AnilistService? anilist,
    ProfileSession? profiles,
    Future<Set<String>> Function(Set<String> providers)? openable,
    List<int> Function()? streakTiers,
    Dio? dio,
  }) : _history = history,
       _streakTiers = streakTiers,
       _streak = streak,
       _hive = hive,
       _anilist = anilist,
       _profiles = profiles,
       _openableOf = openable,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 15),
               responseType: ResponseType.bytes,
             ),
           );

  final HistoryService _history;
  final StreakService _streak;
  final HiveService _hive;
  final AnilistService? _anilist;
  final ProfileSession? _profiles;

  /// Whether a title's source is still installed. A widget row whose source
  /// was removed opens onto "details not found", so it is left off.
  /// Of the given sources, the ones installed here. A row on a removed source
  /// would open onto "source unavailable", so the widget leaves it out.
  final Future<Set<String>> Function(Set<String> providers)? _openableOf;

  /// The streak badge's tiers, in days, as the server has them.
  final List<int> Function()? _streakTiers;

  /// Of [providers], the ones whose source is installed here. Mangayomi
  /// sources are known on this side ([mangayomi]); the native hosts' are asked
  /// of [host], once per host, with the ids bare. A host that cannot say
  /// (null) keeps its rows, and anything that is not an extension source —
  /// the server's, a catalogue — is always kept.
  static Future<Set<String>> installedOf(
    Set<String> providers, {
    required bool Function(String provider) mangayomi,
    required Future<Set<String>?> Function(String prefix, List<String> ids)
    host,
  }) async {
    final keep = <String>{};
    final byHost = <String, List<String>>{};
    for (final p in providers) {
      final prefix = p.length > 3 ? p.substring(0, 3) : '';
      if (prefix == 'my:') {
        if (mangayomi(p)) keep.add(p);
      } else if (prefix == 'mn:' || prefix == 'an:' || prefix == 'cs:') {
        (byHost[prefix] ??= []).add(p.substring(3));
      } else {
        keep.add(p);
      }
    }
    for (final MapEntry(key: prefix, value: ids) in byHost.entries) {
      final found = await host(prefix, ids);
      for (final id in ids) {
        if (found == null || found.contains(id)) keep.add('$prefix$id');
      }
    }
    return keep;
  }

  Future<Set<String>> _openable(Set<String> providers) async {
    final check = _openableOf;
    if (check == null) return providers;
    try {
      return await check(providers);
    } catch (_) {
      return providers;
    }
  }

  final Dio _dio;

  static const MethodChannel _channel = MethodChannel('sozo/home_widget');

  static bool get supported => !kIsWeb && Platform.isAndroid && !isTvPlatform;

  /// How many titles the widgets can show.
  static const int _slots = 3;

  Timer? _debounce;
  bool _started = false;

  /// Moves the app onto a title's source (and so its mode) before it opens:
  /// Home only ever continues a title from its own mode, and a manga opened
  /// while the app sat in Watch came up as an empty video page.
  void Function(String provider)? selectSource;

  /// The source the app is on now, to tell whether a move is needed.
  String Function()? currentSource;

  /// Whether the launcher can take a widget straight from the app.
  Future<bool> canPin() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('canPin') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// How many of each widget — `streak`, `continue` — are on the home screen.
  Future<Map<String, int>> placed() async {
    if (!supported) return const {};
    try {
      final raw = await _channel.invokeMethod<Map>('placed');
      return {
        for (final e in (raw ?? const {}).entries)
          '${e.key}': (e.value as num?)?.toInt() ?? 0,
      };
    } catch (_) {
      return const {};
    }
  }

  /// Asks the launcher to add a widget — `streak`, `continue` or `small` —
  /// with its own "add to home screen" sheet. False when it could not ask.
  Future<bool> pin(String kind) async {
    if (!supported) return false;
    // The new widget draws from the snapshot; make sure there is a fresh one.
    unawaited(push());
    try {
      return await _channel.invokeMethod<bool>('pin', kind) ?? false;
    } catch (_) {
      return false;
    }
  }

  void start() {
    if (!supported || _started) return;
    _started = true;
    _history.revision.addListener(_soon);
    _streak.state.addListener(_soon);
    _profiles?.addListener(_soon);
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'action' && call.arguments is Map) {
        _handle((call.arguments as Map).cast<String, dynamic>());
      }
      return null;
    });
    _takeLaunchAction();
    _soon();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving the app is when the widget is looked at next: whatever changed
    // in this session — a lock just turned on, an episode just finished —
    // should be on the home screen by then.
    if (state == AppLifecycleState.paused) unawaited(push());
  }

  void _soon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => unawaited(push()));
  }

  bool _pushing = false;

  Future<void> push() async {
    if (!supported || _pushing) return;
    _pushing = true;
    try {
      final snapshot = await _snapshot();
      await _channel.invokeMethod('update', jsonEncode(snapshot));
    } catch (e) {
      debugPrint('[home_widget] update failed: $e');
    } finally {
      _pushing = false;
    }
  }

  // --- the snapshot ----------------------------------------------------------

  Future<Map<String, dynamic>> _snapshot() async {
    final labels = {
      'continue': 'home.continue_watching'.tr(),
      'next': 'home_widget.next'.tr(),
      'outNow': 'home_widget.out_now'.tr(),
      'locked': 'home_widget.locked'.tr(),
      'lockedHint': 'home_widget.locked_hint'.tr(),
      'atRisk': 'home_widget.at_risk'.tr(),
      'empty': 'home_widget.empty'.tr(),
      'days': 'home_widget.days'.tr(),
      'd': 'home_widget.d'.tr(),
      'h': 'home_widget.h'.tr(),
      'm': 'home_widget.m'.tr(),
      'streakDays': 'home_widget.streak_days'.tr(),
      'streakStart': 'home_widget.streak_start'.tr(),
      'streakDone': 'home_widget.streak_done'.tr(),
      'streakTonight': 'home_widget.streak_tonight'.tr(),
    };
    // A locked app shows nothing of what was watched — not on the lock
    // screen's doorstep, the home screen. Nor does a profile behind its own
    // PIN: the phone is shared, and the home screen is the most shared part.
    final active = _profiles?.active;
    if (_hive.isAppLockEnabled || (active?.hasPin ?? false)) {
      await _prunePosters(const {});
      return {'locked': true, 'labels': labels};
    }
    final all = _history.getAll();
    final openable = await _openable({for (final i in all) i.provider});
    final items = continueItems([
      for (final item in all)
        if (openable.contains(item.provider)) item,
    ]);
    final posters = <String>{};
    // Whose it is, when there is more than one to be: the profile's avatar
    // in the corner, never its name — a face reads at a glance.
    String? avatar;
    final profiles = _profiles;
    if (active != null && profiles != null && profiles.profiles.length > 1) {
      avatar = await _avatar(active);
      if (avatar != null) posters.add(avatar);
    }
    final rows = <Map<String, dynamic>>[];
    for (final item in items) {
      final path = await _poster(item.thumbnail);
      if (path != null) posters.add(path);
      rows.add({
        'title': item.title,
        'subtitle': subtitleOf(item),
        'progress': item.progress,
        'poster': ?path,
        'contentUrl': item.contentUrl,
        'provider': item.provider,
        'episodeIndex': ?item.episodeIndex,
      });
    }
    final streak = _streak.state.value;
    final badge = streakBadge(
      streak.current,
      _streakTiers?.call() ?? const [7, 30, 100, 365],
    );
    String? medal;
    if (_hive.isLoggedIn) {
      medal = await _streakMedal(streak.current, badge);
      if (medal != null) posters.add(medal);
    }
    await _prunePosters(posters);
    return {
      'locked': false,
      'labels': labels,
      'items': rows,
      'avatar': ?avatar,
      if (_hive.isLoggedIn)
        'streak': {
          'current': streak.current,
          'longest': streak.longest,
          'lastActiveDate': ?streak.lastActiveDate,
          'medal': ?medal,
          // The way to the next badge, under the week; none once all are won.
          if (badge.next != null)
            'nextLine': 'home_widget.streak_next'.tr(
              namedArgs: {
                'left': '${badge.next! - streak.current}',
                'target': '${badge.next}',
              },
            ),
          // The last seven days, today last, as dots; a date per dot so the
          // widget can tell which one is today, and its weekday's initial
          // under it — without one a row of dots said nothing about when.
          'week': [
            for (final d in streak.weeklyActivity)
              {
                'date': d.date,
                'active': d.active,
                'letter': ?_weekdayInitial(d.date),
              },
          ],
        },
      'next': ?await _nextAiring(),
    };
  }

  /// The titles Home offers to continue, newest first: one row per title,
  /// finished films left out — the same rule as the Continue watching rail.
  @visibleForTesting
  static List<HistoryItem> continueItems(List<HistoryItem> all) {
    final byContent = <String, HistoryItem>{};
    for (final item in all) {
      if (item.contentUrl.isEmpty) continue;
      if (item.progress >= 0.95 && !item.isSerial) continue;
      final had = byContent[item.contentUrl];
      if (had == null || item.watchedAt > had.watchedAt) {
        byContent[item.contentUrl] = item;
      }
    }
    final out = byContent.values.toList()
      ..sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
    return out.take(_slots).toList();
  }

  /// "Ep 7", "Ch 128" — the number and nothing else. A chapter's own title
  /// ("Chapter 1: My Worst Nightmare") and the minutes left made three lines
  /// of small print per poster; the progress bar already says how far.
  @visibleForTesting
  static String subtitleOf(HistoryItem item) {
    if (!item.isSerial) return '';
    // Rows written before the media type was recorded have none; the
    // source's own mode says whether it is read or watched.
    final reading = item.mediaType != null
        ? item.mediaType == 'manga' || item.mediaType == 'novel'
        : item.provider.contentMode != ContentMode.video;
    final number = item.episodeNumber ?? item.episodeIndex;
    if (number != null) {
      return (reading ? 'home_widget.chapter' : 'home_widget.episode').tr(
        args: ['$number'],
      );
    }
    final label = item.episodeLabel?.trim() ?? '';
    return label;
  }

  // --- posters ---------------------------------------------------------------

  Directory? _dir;

  Future<Directory> _posterDir() async {
    final cached = _dir;
    if (cached != null) return cached;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/home_widget');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  /// A poster the widget can read: fetched once per image, shrunk to the
  /// largest size a widget draws it, kept until it leaves the snapshot.
  Future<String?> _poster(String? url) async {
    if (url == null || !url.startsWith('http')) return null;
    try {
      final dir = await _posterDir();
      final name = '${md5.convert(utf8.encode(url))}.png';
      final file = File('${dir.path}/$name');
      if (await file.exists()) return file.path;
      final res = await _dio.get<List<int>>(url);
      final bytes = res.data;
      if (bytes == null || bytes.isEmpty) return null;
      final codec = await ui.instantiateImageCodec(
        Uint8List.fromList(bytes),
        targetWidth: 360,
      );
      final frame = await codec.getNextFrame();
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      if (png == null) return null;
      await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
      return file.path;
    } catch (e) {
      debugPrint('[home_widget] poster failed: $e');
      return null;
    }
  }

  Future<void> _prunePosters(Set<String> keep) async {
    try {
      final dir = await _posterDir();
      await for (final f in dir.list()) {
        if (f is File && !keep.contains(f.path)) await f.delete();
      }
    } catch (_) {}
  }

  /// Where [current] days stand among the streak badge's [tiers]: how many
  /// are won, the next one's days, and the way to it, 0..1.
  @visibleForTesting
  static ({int tier, int? next, double progress}) streakBadge(
    int current,
    List<int> tiers,
  ) {
    final tier = tiers.where((t) => current >= t).length;
    if (tier >= tiers.length) return (tier: tier, next: null, progress: 1);
    final from = tier == 0 ? 0 : tiers[tier - 1];
    final to = tiers[tier];
    final progress = to <= from
        ? 1.0
        : ((current - from) / (to - from)).clamp(0.0, 1.0);
    return (tier: tier, next: to, progress: progress.toDouble());
  }

  static String? _weekdayInitial(String date) {
    final day = DateTime.tryParse(date);
    if (day == null) return null;
    final name = switch (day.weekday) {
      DateTime.monday => 'streak.weekday_mon'.tr(),
      DateTime.tuesday => 'streak.weekday_tue'.tr(),
      DateTime.wednesday => 'streak.weekday_wed'.tr(),
      DateTime.thursday => 'streak.weekday_thu'.tr(),
      DateTime.friday => 'streak.weekday_fri'.tr(),
      DateTime.saturday => 'streak.weekday_sat'.tr(),
      _ => 'streak.weekday_sun'.tr(),
    };
    return name.isEmpty ? null : name.characters.first;
  }

  /// The streak as its badge: the medal of the tier the streak has reached —
  /// a pewter blank before the first — with the flame struck in it, as on the
  /// achievements page, and the way to the next tier traced round the rim.
  /// The count itself is text beside the label, where it reads at a glance.
  Future<String?> _streakMedal(
    int current,
    ({int tier, int? next, double progress}) badge,
  ) async {
    try {
      final dir = await _posterDir();
      final progress = badge.next == null ? null : badge.progress;
      final key =
          'v4|${current > 0}|${badge.tier}|${progress?.toStringAsFixed(3)}';
      final file = File(
        '${dir.path}/medal_${md5.convert(utf8.encode(key))}.png',
      );
      if (await file.exists()) return file.path;
      // Room round the medal for its halo and shadow.
      const px = 240.0;
      const medalPx = 176.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const center = Offset(px / 2, px / 2);
      // The warmth of the flame behind it, stronger the longer the streak.
      final warmth = current <= 0 ? 0.10 : (0.22 + badge.tier * 0.06);
      canvas.drawCircle(
        center,
        px / 2,
        Paint()
          ..shader = ui.Gradient.radial(center, px / 2, [
            const Color(0xFFFF8A3D).withValues(alpha: warmth),
            const Color(0x00FF8A3D),
          ]),
      );
      canvas.save();
      canvas.translate((px - medalPx) / 2, (px - medalPx) / 2);
      paintMedal(
        canvas,
        const Size.square(medalPx),
        tier: MedalTier.ofLevel(badge.tier),
        icon: AchievementDef.of('streak').icon,
        progress: progress,
      );
      canvas.restore();
      final picture = recorder.endRecording();
      final out = await picture.toImage(px.toInt(), px.toInt());
      final png = await out.toByteData(format: ui.ImageByteFormat.png);
      out.dispose();
      if (png == null) return null;
      await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
      return file.path;
    } catch (e) {
      debugPrint('[home_widget] streak medal failed: $e');
      return null;
    }
  }

  /// The profile's avatar as a small round picture the widget can draw: its
  /// illustration on its colour, else its preset icon or initial.
  Future<String?> _avatar(HouseholdProfile profile) async {
    try {
      final dir = await _posterDir();
      final key =
          '${profile.id}|${profile.avatar}|${profile.color}|${profile.name}';
      final file = File(
        '${dir.path}/avatar_${md5.convert(utf8.encode(key))}.png',
      );
      if (await file.exists()) return file.path;
      const px = 96.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final center = const Offset(px / 2, px / 2);
      final asset = ProfileAvatars.imageFor(profile.avatar);
      final bg = ProfileAvatars.parse(
        asset != null
            ? ProfileAvatars.imageColors[profile.avatar]
            : profile.color,
        profile.name,
      );
      canvas.drawCircle(center, px / 2, Paint()..color = bg);
      if (asset != null) {
        final data = await rootBundle.load(asset);
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(),
          targetWidth: px.toInt(),
        );
        final image = (await codec.getNextFrame()).image;
        canvas.save();
        canvas.clipPath(Path()..addOval(Offset.zero & const Size(px, px)));
        canvas.drawImageRect(
          image,
          Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
          Offset.zero & const Size(px, px),
          Paint()..filterQuality = FilterQuality.medium,
        );
        canvas.restore();
        image.dispose();
      } else {
        final icon = ProfileAvatars.presets[profile.avatar];
        final painter = TextPainter(
          textDirection: ui.TextDirection.ltr,
          text: TextSpan(
            text: icon != null
                ? String.fromCharCode(icon.codePoint)
                : (profile.name.trim().isEmpty
                      ? '?'
                      : profile.name.trim().characters.first.toUpperCase()),
            style: TextStyle(
              color: const Color(0xFFFFFFFF),
              fontSize: icon != null ? 54 : 48,
              fontWeight: FontWeight.w800,
              fontFamily: icon?.fontFamily,
              package: icon?.fontPackage,
            ),
          ),
        )..layout();
        painter.paint(
          canvas,
          center - Offset(painter.width / 2, painter.height / 2),
        );
      }
      // A thin light ring, so a dark avatar still reads on a dark poster.
      canvas.drawCircle(
        center,
        px / 2 - 2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = const Color(0xCCFFFFFF),
      );
      final picture = recorder.endRecording();
      final out = await picture.toImage(px.toInt(), px.toInt());
      final png = await out.toByteData(format: ui.ImageByteFormat.png);
      out.dispose();
      if (png == null) return null;
      await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
      return file.path;
    } catch (e) {
      debugPrint('[home_widget] avatar failed: $e');
      return null;
    }
  }

  // --- the next episode ------------------------------------------------------

  Map<String, dynamic>? _nextCache;
  DateTime? _nextAt;

  /// The soonest episode due from the viewer's AniList list, or the one that
  /// went out within the day. Asked of AniList at most every few hours.
  Future<Map<String, dynamic>?> _nextAiring() async {
    final anilist = _anilist;
    if (anilist == null || !anilist.isConnected) return null;
    final at = _nextAt;
    if (at != null &&
        DateTime.now().difference(at) < const Duration(hours: 3)) {
      return _nextCache;
    }
    try {
      final entries = await anilist.library();
      final now = DateTime.now();
      ({DateTime at, String title, int episode})? best;
      for (final e in entries) {
        if (e.status != 'CURRENT' && e.status != 'REPEATING') continue;
        final airing = e.media.nextAiring;
        if (airing == null) continue;
        final airs = airing.airsAt;
        if (now.difference(airs) > const Duration(hours: 24)) continue;
        if (best == null || airs.isBefore(best.at)) {
          best = (
            at: airs,
            title: e.media.displayTitle,
            episode: airing.episode,
          );
        }
      }
      _nextAt = DateTime.now();
      _nextCache = best == null
          ? null
          : {
              'title': best.title,
              'episode': 'home_widget.episode'.tr(args: ['${best.episode}']),
              'airsAt': best.at.millisecondsSinceEpoch,
            };
      return _nextCache;
    } catch (e) {
      debugPrint('[home_widget] next airing failed: $e');
      return _nextCache;
    }
  }

  // --- taps ------------------------------------------------------------------

  int _tapSeq = 0;

  /// The poster and name the widget showed, so the page opens on them while
  /// the source answers instead of on an empty frame.
  MovieEntity? _previewOf(String url, String? provider) {
    for (final item in _history.getAll()) {
      if (item.contentUrl != url) continue;
      if (provider != null &&
          provider.isNotEmpty &&
          item.provider != provider) {
        continue;
      }
      return MovieEntity(
        externalId: '',
        title: item.title,
        description: '',
        slug: '',
        url: item.contentUrl,
        provider: item.provider,
        thumbnail: item.thumbnail,
        year: null,
        rating: null,
        qualities: null,
        category: '',
      );
    }
    return null;
  }

  Future<void> _takeLaunchAction() async {
    try {
      final raw = await _channel.invokeMethod<Map>('takeLaunchAction');
      if (raw != null) _handle(raw.cast<String, dynamic>());
    } catch (_) {}
  }

  /// Opens what a widget tap asked for — once Home is up, since a page pushed
  /// over the splash is swept away when the splash hands over to Home.
  void _handle(Map<String, dynamic> action) {
    // A later tap replaces one still waiting for Home.
    final seq = ++_tapSeq;
    void go() {
      switch (action['action']) {
        case 'continue':
          final url = action['contentUrl'] as String?;
          if (url == null || url.isEmpty) return;
          final provider = action['provider'] as String?;
          if (provider != null &&
              provider.isNotEmpty &&
              currentSource?.call() != provider) {
            selectSource?.call(provider);
          }
          AppRouter.router.push(
            '/detail',
            extra: DetailArgs(
              contentUrl: url,
              preview: _previewOf(url, provider),
              autoPlay: true,
              resumeEpisodeIndex: action['episodeIndex'] as int?,
              provider: provider,
            ),
          );
        case 'next':
          AppRouter.router.push('/anilist/calendar');
        case 'streak':
          AppRouter.router.push('/streak');
      }
    }

    final delegate = AppRouter.router.routerDelegate;
    // Past the splash, the first-run pages and "Who's watching?". A title
    // opened over the profile picker loaded before any profile — and so any
    // of its sources — was chosen, came up blank, and Back led to the picker.
    bool atHome() {
      final path = delegate.currentConfiguration.uri.path;
      return path.isNotEmpty &&
          path != '/splash' &&
          path != '/onboarding' &&
          !path.startsWith('/profiles');
    }

    // Home up, and the sources known — on a cold start the tap arrives before
    // either, and a title opened then lands on the wrong source. Picking a
    // profile takes as long as it takes, so that wait has no limit; the one
    // for the source list, once home, gives up after five seconds.
    var tries = 0;
    void whenReady() {
      if (seq != _tapSeq) return;
      if (atHome() && (selectSource != null || tries++ > 20)) {
        go();
        return;
      }
      Timer(const Duration(milliseconds: 250), whenReady);
    }

    whenReady();
  }
}
