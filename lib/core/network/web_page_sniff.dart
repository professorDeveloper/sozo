/// How many leading bytes [looksLikeWebPage] needs to be sure: room for a BOM
/// and blank lines ahead of the markup.
const int webPageSniffBytes = 512;

/// Whether the first bytes of a body are a web page rather than media.
///
/// Not the Content-Type: disguised HLS CDNs label real MPEG-TS `text/html`
/// (vidapi's `page-N.html`, anikoto's `seg-N-….html`, checked 2026-10-25), and
/// the player, which never reads that header, plays them. Deciding by the
/// header failed every such episode as "the source sent a web page".
///
/// Only markup counts: an AES-128 segment is random bytes, so "starts like TS"
/// cannot be the test. An SVG or XML prolog is not refused either, since a
/// comic page can be one. Same rule as `HlsDownloadPlaylist.looksLikeWebPage`
/// on Android, so both downloaders refuse the same answers.
bool looksLikeWebPage(List<int> head) {
  var i = 0;
  if (head.length >= 3 &&
      head[0] == 0xEF &&
      head[1] == 0xBB &&
      head[2] == 0xBF) {
    i = 3;
  }
  while (i < head.length && _isMarkupSpace(head[i])) {
    i++;
  }
  final end = i + _prefixBytes > head.length ? head.length : i + _prefixBytes;
  if (end <= i) return false;
  final text = String.fromCharCodes(head.sublist(i, end)).toLowerCase();
  return _webPageStarts.any(text.startsWith);
}

const int _prefixBytes = 16;

const List<String> _webPageStarts = [
  '<!doctype html',
  '<html',
  '<head',
  '<body',
  '<title',
  '<script',
  '<meta',
];

bool _isMarkupSpace(int b) =>
    b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D || b == 0x0C;
