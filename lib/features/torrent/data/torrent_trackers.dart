/// Public BitTorrent trackers injected into every magnet Sozo opens.
///
/// This is the single highest-impact detail in the whole torrent feature, and
/// the easiest to skip. Anime magnets from an indexer usually carry only the
/// tracker that site runs, and half the time nothing at all — which leaves the
/// client on DHT alone. DHT bootstraps slowly on mobile networks, is disabled
/// for torrents flagged private, and is the difference between a stream that
/// starts in three seconds and one that never starts.
///
/// The list mirrors the one CloudStream ships (`ui/player/Torrent.kt`), with
/// its duplicate entries removed. Every URL here is a public open tracker;
/// none of them require an account, and none are private-tracker announces —
/// announcing a private torrent to a public tracker is a rules violation on
/// every private tracker that exists, so nothing from a private source should
/// ever be passed through [defaults].
abstract final class TorrentTrackers {
  static const List<String> defaults = [
    'udp://tracker.opentrackr.org:1337/announce',
    'udp://open.tracker.cl:1337/announce',
    'udp://open.demonii.com:1337/announce',
    'udp://opentracker.i2p.rocks:6969/announce',
    'udp://tracker.openbittorrent.com:6969/announce',
    'http://tracker.openbittorrent.com:80/announce',
    'udp://open.stealth.si:80/announce',
    'udp://exodus.desync.com:6969/announce',
    'udp://explodie.org:6969/announce',
    'udp://tracker-udp.gbitt.info:80/announce',
    'https://tracker.gbitt.info:443/announce',
    'http://tracker.gbitt.info:80/announce',
    'udp://uploads.gamecoast.net:6969/announce',
    'udp://tracker1.bt.moack.co.kr:80/announce',
    'udp://tracker.tiny-vps.com:6969/announce',
    'udp://tracker.theoks.net:6969/announce',
    'udp://tracker.dump.cl:6969/announce',
    'udp://tracker.bittor.pw:1337/announce',
    'https://tracker2.ctix.cn/announce',
    'https://tracker1.520.jp:443/announce',
  ];

  /// Nyaa runs its own tracker and every Nyaa torrent announces to it. Adding
  /// it explicitly helps when a magnet was rebuilt from a bare info hash.
  static const List<String> nyaa = [
    'http://nyaa.tracker.wf:7777/announce',
    'udp://tracker.coppersurfer.tk:6969/announce',
  ];

  /// Everything to attach to a magnet from [indexerId].
  static List<String> forIndexer(String indexerId) => switch (indexerId) {
        'nyaa' || 'sukebei' || 'tokyotosho' => [...nyaa, ...defaults],
        _ => defaults,
      };
}
