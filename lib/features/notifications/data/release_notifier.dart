import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';

import 'package:soplay/features/notifications/data/notification_payload.dart';

/// The words a notification needs, captured while a locale is loaded.
///
/// The background worker and the push handler run in isolates with no
/// `easy_localization` in them, so the app writes these down (see
/// ReleaseWatchSnapshot) and they read them back. Templates keep their `{}`
/// placeholders and are filled here.
class NotificationLabels {
  const NotificationLabels({
    this.channelGeneral = 'Notifications',
    this.channelGeneralDesc = 'Account, friends and announcements',
    this.channelReleases = 'New episodes',
    this.channelReleasesDesc = 'New episodes and chapters of titles you follow',
    this.channelAiring = 'Airing reminders',
    this.channelAiringDesc = 'Shortly before an episode you follow airs',
    this.channelQuiet = 'Quiet hours',
    this.channelQuietDesc = 'Delivered silently during your quiet hours',
    this.episodeOne = 'Episode {} is out',
    this.episodesMany = '{} new episodes · up to {}',
    this.chapterOne = 'Chapter {} is out',
    this.chaptersMany = '{} new chapters · up to {}',
    this.actionWatch = 'Watch',
    this.actionRead = 'Read',
    this.actionSeen = 'Mark seen',
    this.summaryTitle = 'New episodes',
    this.summaryMore = '{} titles have something new',
    this.badgeEpisode = 'NEW EPISODE',
    this.badgeChapter = 'NEW CHAPTER',
    this.epShort = 'EP',
    this.chShort = 'CH',
  });

  final String channelGeneral;
  final String channelGeneralDesc;
  final String channelReleases;
  final String channelReleasesDesc;
  final String channelAiring;
  final String channelAiringDesc;
  final String channelQuiet;
  final String channelQuietDesc;
  final String episodeOne;
  final String episodesMany;
  final String chapterOne;
  final String chaptersMany;
  final String actionWatch;
  final String actionRead;
  final String actionSeen;
  final String summaryTitle;
  final String summaryMore;
  final String badgeEpisode;
  final String badgeChapter;
  final String epShort;
  final String chShort;

  static String fill(String template, List<Object> args) {
    var out = template;
    for (final a in args) {
      out = out.replaceFirst('{}', '$a');
    }
    return out;
  }

  String bodyFor(ReleaseAlert a) {
    final server = a.body;
    if (server != null && server.isNotEmpty) return server;
    final reading = a.isReading;
    if (a.count > 1) {
      return fill(reading ? chaptersMany : episodesMany, [a.count, a.episodeText]);
    }
    return fill(reading ? chapterOne : episodeOne, [a.episodeText]);
  }

  Map<String, String> toJson() => {
    'cg': channelGeneral,
    'cgd': channelGeneralDesc,
    'cr': channelReleases,
    'crd': channelReleasesDesc,
    'ca': channelAiring,
    'cad': channelAiringDesc,
    'cq': channelQuiet,
    'cqd': channelQuietDesc,
    'e1': episodeOne,
    'en': episodesMany,
    'c1': chapterOne,
    'cn': chaptersMany,
    'aw': actionWatch,
    'ar': actionRead,
    'as': actionSeen,
    'st': summaryTitle,
    'sm': summaryMore,
    'be': badgeEpisode,
    'bc': badgeChapter,
    'es': epShort,
    'cs': chShort,
  };

  factory NotificationLabels.fromJson(Object? raw) {
    const d = NotificationLabels();
    if (raw is! Map) return d;
    String v(String k, String fallback) {
      final s = raw[k];
      return s is String && s.isNotEmpty ? s : fallback;
    }

    return NotificationLabels(
      channelGeneral: v('cg', d.channelGeneral),
      channelGeneralDesc: v('cgd', d.channelGeneralDesc),
      channelReleases: v('cr', d.channelReleases),
      channelReleasesDesc: v('crd', d.channelReleasesDesc),
      channelAiring: v('ca', d.channelAiring),
      channelAiringDesc: v('cad', d.channelAiringDesc),
      channelQuiet: v('cq', d.channelQuiet),
      channelQuietDesc: v('cqd', d.channelQuietDesc),
      episodeOne: v('e1', d.episodeOne),
      episodesMany: v('en', d.episodesMany),
      chapterOne: v('c1', d.chapterOne),
      chaptersMany: v('cn', d.chaptersMany),
      actionWatch: v('aw', d.actionWatch),
      actionRead: v('ar', d.actionRead),
      actionSeen: v('as', d.actionSeen),
      summaryTitle: v('st', d.summaryTitle),
      summaryMore: v('sm', d.summaryMore),
      badgeEpisode: v('be', d.badgeEpisode),
      badgeChapter: v('bc', d.badgeChapter),
      epShort: v('es', d.epShort),
      chShort: v('cs', d.chShort),
    );
  }
}

/// A followed title with something new, as a notification sees it.
class ReleaseAlert {
  const ReleaseAlert({
    required this.provider,
    required this.contentUrl,
    required this.title,
    required this.episodeNumber,
    this.thumbnail = '',
    this.mode = 'video',
    this.episodeLabel,
    this.count = 1,
    this.profileId,
    this.body,
  });

  final String provider;
  final String contentUrl;
  final String title;
  final String thumbnail;
  final String mode;

  /// The newest episode or chapter.
  final int episodeNumber;
  final String? episodeLabel;

  /// How many are new, counting [episodeNumber].
  final int count;

  /// The household profile a push was addressed to. Carried into the tap so
  /// opening it switches to that profile.
  final String? profileId;

  /// The server's own wording, in the account's language; it knows seasons,
  /// which a running number here does not.
  final String? body;

  bool get isReading => mode == 'manga' || mode == 'novel';

  /// The first new one — what "Watch" should open at.
  int get firstNew => (episodeNumber - count + 1).clamp(1, episodeNumber);

  String get episodeText {
    final label = episodeLabel?.trim();
    if (label != null && label.isNotEmpty && count <= 1) return label;
    return '$episodeNumber';
  }

  /// Push data (`type: new_release`) read into an alert, or null when it does
  /// not name a title.
  static ReleaseAlert? fromData(Map<String, dynamic> data) {
    final url = data['contentUrl']?.toString() ?? '';
    final episode = int.tryParse('${data['episodeNumber'] ?? ''}') ?? 0;
    if (url.isEmpty || episode <= 0) return null;
    final count = int.tryParse('${data['count'] ?? ''}') ?? 1;
    final profile = data['profileId']?.toString() ?? '';
    final body = data['body']?.toString().trim() ?? '';
    return ReleaseAlert(
      provider: data['provider']?.toString() ?? '',
      contentUrl: url,
      title: data['title']?.toString() ?? '',
      thumbnail: data['thumbnail']?.toString() ?? '',
      mode: data['mode']?.toString() ?? 'video',
      episodeNumber: episode,
      episodeLabel: data['episodeLabel']?.toString(),
      count: count < 1 ? 1 : count,
      profileId: profile.isEmpty ? null : profile,
      body: body.isEmpty ? null : body,
    );
  }

  Map<String, dynamic> toPayload() => {
    'type': 'new_release',
    'provider': provider,
    'contentUrl': contentUrl,
    'mode': mode,
    'episodeNumber': firstNew,
    'title': title,
    'profileId': ?profileId,
  };
}

/// Draws release notifications the same way from every isolate: the app, the
/// periodic background check and the push handler.
class ReleaseNotifier {
  ReleaseNotifier(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  static const String generalChannel = 'soplay_default';
  static const String releasesChannel = 'sozo_releases';
  static const String airingChannel = 'sozo_airing';
  static const String quietChannel = 'sozo_quiet';
  static const String group = 'sozo.releases';
  static const String smallIcon = '@drawable/ic_stat_sozo';
  static const ui.Color accent = ui.Color(0xFFE50914);

  static const int summaryId = 0x50E0;
  static const String actionOpen = 'open';
  static const String actionSeen = 'seen';

  /// One id per title, so a newer episode replaces the older notification
  /// instead of stacking under it. FNV-1a rather than `String.hashCode`, which
  /// Dart does not promise to keep stable between isolates or releases.
  static int idFor(String provider, String contentUrl) {
    var hash = 0x811c9dc5;
    for (final unit in '$provider|$contentUrl'.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    // Clear of the airing reminders' block and the fixed ids below 0x10000.
    return 0x100000 + (hash & 0x0fffffff);
  }

  static List<AndroidNotificationChannel> channels(NotificationLabels l) => [
    AndroidNotificationChannel(
      generalChannel,
      l.channelGeneral,
      description: l.channelGeneralDesc,
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      releasesChannel,
      l.channelReleases,
      description: l.channelReleasesDesc,
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      airingChannel,
      l.channelAiring,
      description: l.channelAiringDesc,
    ),
    AndroidNotificationChannel(
      quietChannel,
      l.channelQuiet,
      description: l.channelQuietDesc,
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    ),
  ];

  /// Creates the channels, or renames them after a language change — Android
  /// keeps the importance a person chose and only takes the new words.
  Future<void> ensureChannels(NotificationLabels labels) async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    for (final c in channels(labels)) {
      await android.createNotificationChannel(c);
    }
  }

  Future<void> showRelease(
    ReleaseAlert alert,
    NotificationLabels labels, {
    bool quiet = false,
  }) async {
    final id = idFor(alert.provider, alert.contentUrl);
    final body = labels.bodyFor(alert);
    final art = await PosterArt.prepare(alert, labels);
    final channel = quiet ? quietChannel : releasesChannel;
    final style = art.banner != null
        ? BigPictureStyleInformation(
            FilePathAndroidBitmap(art.banner!),
            largeIcon: art.icon == null ? null : FilePathAndroidBitmap(art.icon!),
            contentTitle: alert.title,
            summaryText: body,
            hideExpandedLargeIcon: true,
          )
        : BigTextStyleInformation(body, contentTitle: alert.title);
    final android = AndroidNotificationDetails(
      channel,
      quiet ? labels.channelQuiet : labels.channelReleases,
      channelDescription: quiet
          ? labels.channelQuietDesc
          : labels.channelReleasesDesc,
      icon: smallIcon,
      color: accent,
      importance: quiet ? Importance.low : Importance.high,
      priority: quiet ? Priority.low : Priority.high,
      silent: quiet,
      styleInformation: style,
      largeIcon: art.icon == null ? null : FilePathAndroidBitmap(art.icon!),
      groupKey: group,
      category: AndroidNotificationCategory.recommendation,
      when: DateTime.now().millisecondsSinceEpoch,
      actions: [
        AndroidNotificationAction(
          actionOpen,
          alert.isReading ? labels.actionRead : labels.actionWatch,
          showsUserInterface: true,
        ),
        AndroidNotificationAction(actionSeen, labels.actionSeen),
      ],
    );
    await _plugin.show(
      id,
      alert.title.isEmpty ? labels.summaryTitle : alert.title,
      body,
      NotificationDetails(
        android: android,
        iOS: const DarwinNotificationDetails(threadIdentifier: group),
      ),
      payload: encodeNotificationPayload(alert.toPayload()),
    );
    await refreshSummary(labels, quiet: quiet);
  }

  /// A summary once two or more titles are waiting, so the shade shows one
  /// "3 titles have something new" group rather than a wall of cards.
  Future<void> refreshSummary(NotificationLabels labels, {bool quiet = false}) async {
    if (!Platform.isAndroid) return;
    List<ActiveNotification> active;
    try {
      active = await _plugin.getActiveNotifications();
    } catch (_) {
      return;
    }
    final children = [
      for (final n in active)
        if (n.groupKey == group && n.id != summaryId) n,
    ];
    if (children.length < 2) {
      await _plugin.cancel(summaryId);
      return;
    }
    final more = NotificationLabels.fill(labels.summaryMore, [children.length]);
    await _plugin.show(
      summaryId,
      labels.summaryTitle,
      more,
      NotificationDetails(
        android: AndroidNotificationDetails(
          quiet ? quietChannel : releasesChannel,
          quiet ? labels.channelQuiet : labels.channelReleases,
          icon: smallIcon,
          color: accent,
          groupKey: group,
          setAsGroupSummary: true,
          groupAlertBehavior: GroupAlertBehavior.children,
          onlyAlertOnce: true,
          styleInformation: InboxStyleInformation(
            [
              for (final n in children.take(6))
                '${n.title ?? ''}  ·  ${n.body ?? ''}',
            ],
            contentTitle: labels.summaryTitle,
            summaryText: more,
          ),
        ),
      ),
      payload: encodeNotificationPayload(const {'type': 'releases_feed'}),
    );
  }

  Future<void> cancelFor(String provider, String contentUrl, NotificationLabels labels) async {
    await _plugin.cancel(idFor(provider, contentUrl));
    await refreshSummary(labels);
  }
}

/// The poster, downloaded once and turned into the two images a rich
/// notification wants: a square-ish large icon and a 2:1 banner.
///
/// The banner is composed rather than the poster used as-is: Android crops a
/// big picture to roughly 2:1, which cuts a portrait poster to a strip across
/// someone's chin. Composed, the poster sits whole on a blurred copy of
/// itself with the episode number beside it.
class PosterArt {
  const PosterArt({this.icon, this.banner});

  final String? icon;
  final String? banner;

  static const int _maxBytes = 3 * 1024 * 1024;

  static Future<PosterArt> prepare(ReleaseAlert alert, NotificationLabels l) async {
    final url = alert.thumbnail.trim();
    if (url.isEmpty || !url.startsWith('http')) return const PosterArt();
    try {
      final dir = Directory(
        '${(await getTemporaryDirectory()).path}/release_posters',
      );
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final stem = ReleaseNotifier.idFor(alert.provider, alert.contentUrl);
      final icon = File('${dir.path}/$stem.img');
      if (!icon.existsSync() ||
          DateTime.now().difference(icon.lastModifiedSync()).inDays > 7) {
        final bytes = await _download(url);
        if (bytes == null) return const PosterArt();
        await icon.writeAsBytes(bytes, flush: true);
      }
      String? banner;
      try {
        final out = File('${dir.path}/$stem-${alert.episodeNumber}.png');
        if (!out.existsSync()) {
          final png = await _compose(
            await icon.readAsBytes(),
            badge: alert.isReading ? l.badgeChapter : l.badgeEpisode,
            number: '${alert.isReading ? l.chShort : l.epShort} ${alert.episodeText}',
          );
          if (png != null) await out.writeAsBytes(png, flush: true);
        }
        if (out.existsSync()) banner = out.path;
      } catch (e) {
        if (kDebugMode) debugPrint('[release-art] compose failed: $e');
      }
      return PosterArt(icon: icon.path, banner: banner);
    } catch (_) {
      return const PosterArt();
    }
  }

  static Future<Uint8List?> _download(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Linux; Android 14) Sozo');
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in res.timeout(const Duration(seconds: 12))) {
        builder.add(chunk);
        if (builder.length > _maxBytes) return null;
      }
      final bytes = builder.takeBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<Uint8List?> _compose(
    Uint8List poster, {
    required String badge,
    required String number,
  }) async {
    const w = 1024.0, h = 512.0;
    final codec = await ui.instantiateImageCodec(poster, targetHeight: 720);
    final image = (await codec.getNextFrame()).image;
    final iw = image.width.toDouble(), ih = image.height.toDouble();
    final full = ui.Rect.fromLTWH(0, 0, w, h);

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, full);

    final coverScale = (w / iw) > (h / ih) ? w / iw : h / ih;
    final cw = w / coverScale, ch = h / coverScale;
    final coverSrc = ui.Rect.fromLTWH((iw - cw) / 2, (ih - ch) / 2, cw, ch);
    canvas.saveLayer(
      full,
      ui.Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
    );
    canvas.drawImageRect(image, coverSrc, full.inflate(40), ui.Paint());
    canvas.restore();
    canvas.drawRect(
      full,
      ui.Paint()
        ..shader = ui.Gradient.linear(
          const ui.Offset(0, 0),
          const ui.Offset(w, 0),
          [const ui.Color(0x66000000), const ui.Color(0xD9000000)],
        ),
    );

    const cardH = 424.0;
    final cardW = (cardH * iw / ih).clamp(200.0, 340.0);
    final card = ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(56, (h - cardH) / 2, cardW, cardH),
      const ui.Radius.circular(22),
    );
    canvas.drawRRect(
      card.shift(const ui.Offset(0, 10)),
      ui.Paint()
        ..color = const ui.Color(0x99000000)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 18),
    );
    canvas.save();
    canvas.clipRRect(card);
    final fitScale = (cardW / iw) > (cardH / ih) ? cardW / iw : cardH / ih;
    final fw = cardW / fitScale, fh = cardH / fitScale;
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH((iw - fw) / 2, (ih - fh) / 2, fw, fh),
      card.outerRect,
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    canvas.restore();

    final textLeft = 56 + cardW + 48;
    final textWidth = w - textLeft - 48;
    ui.Paragraph para(String text, double size, ui.Color color, ui.FontWeight weight, {double spacing = 0}) {
      final b = ui.ParagraphBuilder(
        ui.ParagraphStyle(maxLines: 1, ellipsis: '…', textDirection: ui.TextDirection.ltr),
      )
        ..pushStyle(
          ui.TextStyle(
            color: color,
            fontSize: size,
            fontWeight: weight,
            letterSpacing: spacing,
          ),
        )
        ..addText(text);
      return b.build()..layout(ui.ParagraphConstraints(width: textWidth));
    }

    final pill = para(badge, 30, const ui.Color(0xFFFFFFFF), ui.FontWeight.w800, spacing: 2);
    final pillRect = ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(textLeft, 150, pill.maxIntrinsicWidth + 40, 56),
      const ui.Radius.circular(28),
    );
    canvas.drawRRect(pillRect, ui.Paint()..color = ReleaseNotifier.accent);
    canvas.drawParagraph(pill, ui.Offset(textLeft + 20, 150 + (56 - pill.height) / 2));
    final big = para(number, 112, const ui.Color(0xFFFFFFFF), ui.FontWeight.w900);
    canvas.drawParagraph(big, ui.Offset(textLeft, 230));

    final picture = recorder.endRecording();
    final out = await picture.toImage(w.toInt(), h.toInt());
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    out.dispose();
    return data?.buffer.asUint8List();
  }
}
