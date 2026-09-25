import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/features/tracker/data/tracker_link_store.dart';

/// How a tracker write went.
///
/// Three outcomes, because the player and the reader used to get one bit back
/// — "an id" or "nothing" — and nothing covered both "there was nothing to
/// write" (an unlinked title, a rewatch behind the list) and "the write never
/// landed" (offline, a 502, a lookup that never answered). Only the second is
/// worth trying again, and with one bit neither could be told from the other,
/// so every failed write was simply lost.
enum TrackerWriteResult {
  /// The tracker has it.
  written,

  /// There was nothing to write, and trying again will not change that.
  skipped,

  /// It did not land, for a reason that says nothing about the title.
  failed,
}

/// A progress write that did not land, waiting to be sent again.
@immutable
class PendingTrackerWrite {
  const PendingTrackerWrite({
    required this.tracker,
    required this.provider,
    required this.contentUrl,
    required this.title,
    required this.number,
    required this.account,
    required this.queuedAt,
    this.attempts = 0,
    this.nextAttemptAt = 0,
  });

  /// Which tracker: `anilist` or `mal`.
  final String tracker;

  final String provider;
  final String contentUrl;
  final String title;

  /// The episode or chapter reached. Only the furthest is kept per title: a
  /// tracker's list holds one number, so sending 4 after 5 is pointless.
  final int number;

  /// The tracker account it was meant for. A write queued for one account must
  /// never land on another, so a switch of account drops it.
  final String account;

  final int queuedAt;
  final int attempts;
  final int nextAttemptAt;

  /// One pending write per tracker per title.
  String get key => '$tracker|${TrackerLinkStore.keyFor(provider, contentUrl)}';

  PendingTrackerWrite copyWith({
    int? number,
    String? title,
    int? attempts,
    int? nextAttemptAt,
  }) => PendingTrackerWrite(
    tracker: tracker,
    provider: provider,
    contentUrl: contentUrl,
    title: title ?? this.title,
    number: number ?? this.number,
    account: account,
    queuedAt: queuedAt,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
  );

  Map<String, dynamic> toJson() => {
    'tracker': tracker,
    'provider': provider,
    'contentUrl': contentUrl,
    'title': title,
    'number': number,
    'account': account,
    'queuedAt': queuedAt,
    'attempts': attempts,
    'nextAttemptAt': nextAttemptAt,
  };

  static PendingTrackerWrite? fromJson(Map<String, dynamic> json) {
    final tracker = json['tracker'];
    final provider = json['provider'];
    final url = json['contentUrl'];
    final number = json['number'];
    final account = json['account'];
    if (tracker is! String ||
        provider is! String ||
        url is! String ||
        number is! num ||
        account is! String) {
      return null;
    }
    return PendingTrackerWrite(
      tracker: tracker,
      provider: provider,
      contentUrl: url,
      title: json['title'] as String? ?? '',
      number: number.toInt(),
      account: account,
      queuedAt: (json['queuedAt'] as num?)?.toInt() ?? 0,
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      nextAttemptAt: (json['nextAttemptAt'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Sends one pending write, reporting how it went.
typedef TrackerSender =
    Future<TrackerWriteResult> Function(PendingTrackerWrite write);

/// Progress writes that failed, kept until they land.
///
/// Playback and reading report to AniList and MyAnimeList fire-and-forget, and
/// rightly: a tracker being down is not the viewer's problem to see mid-episode.
/// But fire-and-forget used to mean forget — an episode finished on a train
/// never reached the list at all. Now a write that failed for a reason that
/// says nothing about the title is written down here, on the device, and sent
/// again when the app comes back to the foreground or starts, with a backoff
/// so a tracker that is down is not hammered.
///
/// ## What it will not do
///
/// Send a write to an account other than the one it was queued for — a switch
/// of account drops it. Send one older than [maxAge]: a month-old episode
/// arriving out of nowhere would read as the app misbehaving. Or hide itself:
/// the connections page shows how many are waiting, and sends them on demand.
class TrackerOutbox extends ChangeNotifier with WidgetsBindingObserver {
  TrackerOutbox({Box? box, int Function()? now})
    : _override = box,
      _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Box? _override;
  Box get _box => _override ?? Hive.box(AppConstants.settingsBox);
  final int Function() _now;

  /// Longest a write waits before it is given up.
  static const Duration maxAge = Duration(days: 30);

  final Map<String, TrackerSender> _senders = {};
  final Map<String, String? Function()> _accounts = {};

  Future<int>? _flushing;

  /// A tracker offering to send its own writes. [account] is the connected
  /// account's id, or null while it is not connected.
  void register(
    String tracker, {
    required TrackerSender send,
    required String? Function() account,
  }) {
    _senders[tracker] = send;
    _accounts[tracker] = account;
  }

  /// Sends whatever is waiting whenever the app comes back to the foreground —
  /// which is when a connection lost in the background has usually returned.
  void start() => WidgetsBinding.instance.addObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(flush());
  }

  List<PendingTrackerWrite> pending([String? tracker]) => [
    for (final w in _read().values)
      if (tracker == null || w.tracker == tracker) w,
  ];

  Map<String, PendingTrackerWrite> _read() {
    final raw = _box.get(AppConstants.trackerOutboxKey);
    if (raw is! String || raw.isEmpty) return {};
    try {
      final list = jsonDecode(raw);
      if (list is! List) return {};
      final out = <String, PendingTrackerWrite>{};
      for (final e in list) {
        if (e is! Map) continue;
        final w = PendingTrackerWrite.fromJson(e.cast<String, dynamic>());
        if (w != null) out[w.key] = w;
      }
      return out;
    } catch (_) {
      // Corrupt — start again rather than fail every write after it.
      return {};
    }
  }

  Future<void> _write(Map<String, PendingTrackerWrite> writes) => _box.put(
    AppConstants.trackerOutboxKey,
    jsonEncode([for (final w in writes.values) w.toJson()]),
  );

  /// Keeps [write] for later. Merged with anything already waiting for the
  /// same title: the furthest number wins, and it is due again at once.
  Future<void> queue(PendingTrackerWrite write) async {
    final all = _read();
    final existing = all[write.key];
    all[write.key] = existing == null || existing.account != write.account
        ? write
        : existing.copyWith(
            number: math.max(existing.number, write.number),
            title: write.title.isNotEmpty ? write.title : existing.title,
            nextAttemptAt: 0,
          );
    await _write(all);
    notifyListeners();
  }

  /// Drops everything waiting for [tracker] — for when it is disconnected.
  Future<void> discard(String tracker) async {
    final all = _read()..removeWhere((_, w) => w.tracker == tracker);
    await _write(all);
    notifyListeners();
  }

  /// Sends what is due; with [force], everything, backoff or not. Returns how
  /// many landed. Calls made while one is running join it.
  Future<int> flush({bool force = false}) =>
      _flushing ??= _flush(force).whenComplete(() => _flushing = null);

  Future<int> _flush(bool force) async {
    var sent = 0;
    for (final write in _read().values) {
      final now = _now();
      if (now - write.queuedAt > maxAge.inMilliseconds) {
        await _drop(write);
        continue;
      }
      final send = _senders[write.tracker];
      final account = _accounts[write.tracker]?.call();
      // Not connected just now: keep it. Connected as someone else: it was
      // never theirs.
      if (send == null || account == null) continue;
      if (account != write.account) {
        await _drop(write);
        continue;
      }
      if (!force && now < write.nextAttemptAt) continue;

      final result = await send(write);
      if (result == TrackerWriteResult.failed) {
        final attempts = write.attempts + 1;
        final all = _read();
        // Only if it is still the same write: a newer episode may have been
        // queued over it while this one was out.
        if (all[write.key]?.number == write.number) {
          all[write.key] = write.copyWith(
            attempts: attempts,
            nextAttemptAt: now + _backoff(attempts).inMilliseconds,
          );
          await _write(all);
        }
      } else {
        if (result == TrackerWriteResult.written) sent++;
        await _drop(write);
      }
    }
    notifyListeners();
    return sent;
  }

  /// Removes [write] unless something newer has replaced it meanwhile.
  Future<void> _drop(PendingTrackerWrite write) async {
    final all = _read();
    final current = all[write.key];
    if (current == null || current.number != write.number) return;
    all.remove(write.key);
    await _write(all);
  }

  /// A minute, doubling, to at most six hours.
  static Duration _backoff(int attempts) =>
      Duration(minutes: math.min(360, 1 << math.min(attempts - 1, 9)));
}
