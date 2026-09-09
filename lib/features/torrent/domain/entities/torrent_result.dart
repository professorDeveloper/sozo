import 'package:soplay/features/torrent/domain/entities/release_info.dart';

/// How likely a torrent is to actually play, judged from its swarm.
///
/// The wiki's rule is that a torrent with no seeders will not download at all,
/// and one seeder on a bad line is barely better. Streaming is harsher than
/// downloading here — a stall mid-episode is a failure, not a delay — so the
/// thresholds are deliberately more conservative than a download client's.
enum SwarmHealth {
  /// The tracker does not report seeder counts at all. Tokyo Toshokan is the
  /// main case: it is an aggregator and simply has no swarm data. Treating
  /// that as zero would grey out every one of its rows, so unknown is its own
  /// state and stays playable.
  unknown,

  dead,
  poor,
  fair,
  good;

  static SwarmHealth fromSeeders(int? seeders) {
    if (seeders == null) return SwarmHealth.unknown;
    if (seeders <= 0) return SwarmHealth.dead;
    if (seeders < 3) return SwarmHealth.poor;
    if (seeders < 15) return SwarmHealth.fair;
    return SwarmHealth.good;
  }

  /// Whether Sozo should let the user tap play without a warning.
  bool get isStreamable => this != SwarmHealth.dead;
}

/// One row from a torrent indexer, normalised across every tracker.
///
/// Trackers expose wildly different shapes — Nyaa has a namespaced RSS with
/// seeder counts and a trusted flag, Tokyo Toshokan buries the magnet in an
/// HTML blob, nekoBT has nothing but scraped markup. Everything downstream
/// (filtering, sorting, the file picker, the player) works on this type only.
class TorrentResult {
  const TorrentResult({
    required this.title,
    required this.indexerId,
    required this.indexerName,
    required this.release,
    this.infoHash,
    this.magnetUrl,
    this.torrentFileUrl,
    this.pageUrl,
    this.seeders,
    this.leechers,
    this.completed,
    this.sizeBytes,
    this.sizeLabel,
    this.publishedAt,
    this.categoryId,
    this.categoryLabel,
    this.trusted = false,
    this.remake = false,
  });

  /// The raw file/release name as the tracker published it.
  final String title;

  /// Stable id of the source indexer, e.g. `nyaa`.
  final String indexerId;

  /// Human label for the badge on the row, e.g. `Nyaa`.
  final String indexerName;

  /// What [title] could be decoded into. Never null — an unparseable name
  /// yields an empty [ReleaseInfo] rather than a missing one.
  final ReleaseInfo release;

  /// 40-character hex BitTorrent v1 info hash, when the tracker exposes one.
  final String? infoHash;

  /// A ready-made magnet, when the tracker publishes one directly.
  final String? magnetUrl;

  /// An HTTP link to a `.torrent` file. TorrServer accepts these as-is, so a
  /// result with only this is still playable.
  final String? torrentFileUrl;

  /// The tracker's own page for this torrent, for "open in browser".
  final String? pageUrl;

  /// Seeders, or null when the tracker does not publish the number. Null is
  /// not zero — see [SwarmHealth.unknown].
  final int? seeders;

  final int? leechers;

  /// Completed downloads ("snatches"). A high count on a low-seed torrent
  /// means it was popular once — worth showing, not worth trusting.
  final int? completed;

  final int? sizeBytes;

  /// The tracker's own size string (`1.4 GiB`), kept when we cannot parse it.
  final String? sizeLabel;

  final DateTime? publishedAt;

  /// Tracker-specific category code, e.g. Nyaa's `1_2`.
  final String? categoryId;
  final String? categoryLabel;

  /// The tracker vouches for the uploader. On Nyaa this is the green row, and
  /// it is a property of the *account*, not of this particular upload — so it
  /// is a strong hint about intent, not a guarantee of quality.
  final bool trusted;

  /// Flagged as a re-upload or modification of someone else's release. Nyaa
  /// shows these in red.
  final bool remake;

  SwarmHealth get health => SwarmHealth.fromSeeders(seeders);

  /// What to hand the torrent engine. Prefers an explicit magnet, falls back
  /// to building one from the info hash, and finally to the `.torrent` URL.
  ///
  /// [extraTrackers] are appended as `tr=` parameters. This matters more than
  /// it looks: a bare `magnet:?xt=urn:btih:...` with no tracker relies purely
  /// on DHT, which is slow to bootstrap and blocked outright for torrents
  /// marked private.
  String? engineLink({List<String> extraTrackers = const []}) {
    if (magnetUrl != null && magnetUrl!.isNotEmpty) {
      return _withTrackers(magnetUrl!, extraTrackers);
    }
    final hash = infoHash;
    if (hash != null && hash.isNotEmpty) {
      final base = StringBuffer('magnet:?xt=urn:btih:$hash')
        ..write('&dn=${Uri.encodeComponent(title)}');
      for (final tracker in extraTrackers) {
        base.write('&tr=${Uri.encodeComponent(tracker)}');
      }
      return base.toString();
    }
    return torrentFileUrl;
  }

  static String _withTrackers(String magnet, List<String> trackers) {
    if (trackers.isEmpty) return magnet;
    final existing = Uri.tryParse(magnet)?.queryParametersAll['tr'] ?? const [];
    final missing = trackers.where((t) => !existing.contains(t));
    if (missing.isEmpty) return magnet;
    final buffer = StringBuffer(magnet);
    for (final tracker in missing) {
      buffer.write('&tr=${Uri.encodeComponent(tracker)}');
    }
    return buffer.toString();
  }

  /// `1.4 GB`-style label, preferring our own formatting of [sizeBytes] and
  /// falling back to whatever string the tracker gave us.
  String? get displaySize {
    final bytes = sizeBytes;
    if (bytes == null) return sizeLabel;
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 100 || unit == 0 ? 0 : 1)} ${units[unit]}';
  }
}
