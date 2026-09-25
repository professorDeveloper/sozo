import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';

import 'package:soplay/features/notifications/data/notification_prefs.dart';
import 'package:soplay/features/notifications/data/release_notifier.dart';
import 'package:soplay/features/tracker/domain/entities/followed_title.dart';

/// Files the app and its background isolates talk through.
///
/// The periodic check and the push handler run in isolates of their own, and
/// Hive is not safe to open from two isolates at once — both keep their own
/// idea of where the file ends and append over each other. So nothing outside
/// the app's own isolate touches Hive. The app writes a [ReleaseWatchSnapshot]
/// of what to check; the others drop one small file per event into the inbox,
/// and the app folds those into Hive when it next runs.
///
/// One file per event so no writer ever reads-modifies-writes a shared file,
/// and a temp-then-rename so a reader never sees half of one.
class ReleaseInbox {
  ReleaseInbox(this.dir);

  final Directory dir;

  static Future<ReleaseInbox> open() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/release_watch');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return ReleaseInbox(dir);
  }

  File get _snapshot => File('${dir.path}/snapshot.json');

  static final math.Random _random = math.Random();

  Future<void> post(ReleaseEvent event) async {
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch.toString().padLeft(17, '0');
    final name = 'evt_${stamp}_${_random.nextInt(1 << 20)}';
    final tmp = File('${dir.path}/$name.tmp');
    await tmp.writeAsString(jsonEncode(event.toJson()), flush: true);
    await tmp.rename('${dir.path}/$name.json');
  }

  List<File> _eventFiles() {
    if (!dir.existsSync()) return const [];
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) {
          final name = f.uri.pathSegments.last;
          return name.startsWith('evt_') && name.endsWith('.json');
        })
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  /// Events not yet taken by the app, oldest first. Left in place.
  List<ReleaseEvent> peek() => [
    for (final f in _eventFiles()) ?_read(f),
  ];

  /// Takes every waiting event, oldest first.
  List<ReleaseEvent> drain() {
    final out = <ReleaseEvent>[];
    for (final f in _eventFiles()) {
      final e = _read(f);
      if (e != null) out.add(e);
      try {
        f.deleteSync();
      } catch (_) {}
    }
    return out;
  }

  ReleaseEvent? _read(File f) {
    try {
      final raw = jsonDecode(f.readAsStringSync());
      return raw is Map ? ReleaseEvent.fromJson(raw.cast<String, dynamic>()) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeSnapshot(ReleaseWatchSnapshot snapshot) async {
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final tmp = File('${dir.path}/snapshot.json.tmp');
    await tmp.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
    await tmp.rename(_snapshot.path);
  }

  ReleaseWatchSnapshot? readSnapshot() {
    try {
      if (!_snapshot.existsSync()) return null;
      final raw = jsonDecode(_snapshot.readAsStringSync());
      return raw is Map ? ReleaseWatchSnapshot.fromJson(raw.cast<String, dynamic>()) : null;
    } catch (_) {
      return null;
    }
  }
}

enum ReleaseEventKind { release, seen }

/// Something a background isolate learned, waiting for the app.
class ReleaseEvent {
  const ReleaseEvent({
    required this.kind,
    required this.provider,
    required this.contentUrl,
    this.title = '',
    this.thumbnail = '',
    this.mode = 'video',
    this.episode = 0,
    this.fromEpisode = 0,
    this.label,
    this.at = 0,
    this.seedOnly = false,
    this.profileId,
    this.scope,
  });

  final ReleaseEventKind kind;
  final String provider;
  final String contentUrl;
  final String title;
  final String thumbnail;
  final String mode;

  /// The highest number now known.
  final int episode;
  final int fromEpisode;
  final String? label;
  final int at;

  /// A first count for a title never checked before: recorded, not news.
  final bool seedOnly;

  /// The household profile a push was addressed to; null for the default
  /// profile, or for anything the device found itself (the active profile).
  final String? profileId;

  /// The profile namespace the snapshot was written for ('' for the default
  /// profile), stamped by the background check.
  final String? scope;

  String get key => FollowedTitle.keyOf(provider, contentUrl);

  factory ReleaseEvent.fromAlert(ReleaseAlert alert, {String? profileId}) =>
      ReleaseEvent(
        kind: ReleaseEventKind.release,
        provider: alert.provider,
        contentUrl: alert.contentUrl,
        title: alert.title,
        thumbnail: alert.thumbnail,
        mode: alert.mode,
        episode: alert.episodeNumber,
        fromEpisode: alert.firstNew,
        label: alert.episodeLabel,
        at: DateTime.now().millisecondsSinceEpoch,
        profileId: profileId,
      );

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'provider': provider,
    'contentUrl': contentUrl,
    if (title.isNotEmpty) 'title': title,
    if (thumbnail.isNotEmpty) 'thumbnail': thumbnail,
    'mode': mode,
    if (episode > 0) 'episode': episode,
    if (fromEpisode > 0) 'from': fromEpisode,
    if (label != null) 'label': label,
    'at': at,
    if (seedOnly) 'seed': true,
    if (profileId != null) 'profileId': profileId,
    if (scope != null) 'scope': scope,
  };

  static ReleaseEvent? fromJson(Map<String, dynamic> j) {
    final url = (j['contentUrl'] ?? '').toString();
    if (url.isEmpty) return null;
    final kind = j['kind'] == 'seen' ? ReleaseEventKind.seen : ReleaseEventKind.release;
    return ReleaseEvent(
      kind: kind,
      provider: (j['provider'] ?? '').toString(),
      contentUrl: url,
      title: (j['title'] ?? '').toString(),
      thumbnail: (j['thumbnail'] ?? '').toString(),
      mode: (j['mode'] ?? 'video').toString(),
      episode: (j['episode'] as num?)?.toInt() ?? 0,
      fromEpisode: (j['from'] as num?)?.toInt() ?? 0,
      label: j['label']?.toString(),
      at: (j['at'] as num?)?.toInt() ?? 0,
      seedOnly: j['seed'] == true,
      profileId: j['profileId']?.toString(),
      scope: j['scope']?.toString(),
    );
  }
}

/// A title the background check should look at.
class WatchedTitle {
  const WatchedTitle({
    required this.provider,
    required this.contentUrl,
    required this.title,
    this.thumbnail = '',
    this.mode = 'video',
    this.count = 0,
    this.notify = true,
  });

  final String provider;
  final String contentUrl;
  final String title;
  final String thumbnail;
  final String mode;
  final int count;
  final bool notify;

  String get key => FollowedTitle.keyOf(provider, contentUrl);

  factory WatchedTitle.of(FollowedTitle t, {required bool notify}) => WatchedTitle(
    provider: t.provider,
    contentUrl: t.contentUrl,
    title: t.title,
    thumbnail: t.thumbnail,
    mode: t.mode,
    count: t.lastEpisodeCount,
    notify: notify,
  );

  Map<String, dynamic> toJson() => {
    'p': provider,
    'u': contentUrl,
    't': title,
    'th': thumbnail,
    'm': mode,
    'c': count,
    if (!notify) 'mute': true,
  };

  static WatchedTitle? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final url = (raw['u'] ?? '').toString();
    final provider = (raw['p'] ?? '').toString();
    if (url.isEmpty || provider.isEmpty) return null;
    return WatchedTitle(
      provider: provider,
      contentUrl: url,
      title: (raw['t'] ?? '').toString(),
      thumbnail: (raw['th'] ?? '').toString(),
      mode: (raw['m'] ?? 'video').toString(),
      count: (raw['c'] as num?)?.toInt() ?? 0,
      notify: raw['mute'] != true,
    );
  }
}

/// What the background check needs, written by the app whenever it changes.
class ReleaseWatchSnapshot {
  const ReleaseWatchSnapshot({
    required this.titles,
    this.prefs = const NotificationPrefs(),
    this.labels = const NotificationLabels(),
    this.adult = false,
    this.writtenAt = 0,
    this.scope = '',
  });

  final List<WatchedTitle> titles;

  /// The profile namespace these titles belong to; '' for the default one.
  final String scope;
  final NotificationPrefs prefs;
  final NotificationLabels labels;
  final bool adult;
  final int writtenAt;

  Map<String, dynamic> toJson() => {
    'v': 1,
    'titles': [for (final t in titles) t.toJson()],
    'prefs': prefs.toJson(),
    'labels': labels.toJson(),
    'adult': adult,
    'at': writtenAt,
    'scope': scope,
  };

  factory ReleaseWatchSnapshot.fromJson(Map<String, dynamic> j) {
    final titles = j['titles'];
    return ReleaseWatchSnapshot(
      titles: [
        if (titles is List)
          for (final t in titles) ?WatchedTitle.fromJson(t),
      ],
      prefs: NotificationPrefs.fromJson(j['prefs']),
      labels: NotificationLabels.fromJson(j['labels']),
      adult: j['adult'] == true,
      writtenAt: (j['at'] as num?)?.toInt() ?? 0,
      scope: (j['scope'] ?? '').toString(),
    );
  }
}
