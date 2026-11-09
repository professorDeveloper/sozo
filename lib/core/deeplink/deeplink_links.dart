import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/watch_party/presentation/party_entry.dart';

const String kDeeplinkHost = 'sozo.azamov.me';
const String kDeeplinkScheme = 'sozo';

/// Where a link opens: a location pushed over Home, with its typed args.
class DeeplinkTarget {
  const DeeplinkTarget(this.location, {this.extra});

  final String location;
  final Object? extra;

  @override
  String toString() => 'DeeplinkTarget($location, $extra)';
}

/// Whether [uri] is one of ours at all: `https://sozo.azamov.me/…` or `sozo://…`.
bool isSozoLink(Uri uri) =>
    (uri.scheme == 'https' && uri.host == kDeeplinkHost) ||
    uri.scheme == kDeeplinkScheme;

/// The route path a link carries. Custom-scheme links keep it in the
/// authority (`sozo://party/CODE` is `/party/CODE`); https links in the path.
String deeplinkPath(Uri uri) {
  if (uri.scheme == kDeeplinkScheme && uri.host.isNotEmpty) {
    return '/${uri.host}${uri.path}';
  }
  return uri.path.isEmpty ? '/${uri.host}' : uri.path;
}

/// What [uri] opens, or null when it opens nothing.
///
/// `/play?url&provider&ep&t` plays: `ep` is the episode number as the viewer
/// sees it, `t` the position in seconds (`95`, `1:35` and `1h2m5s` all read).
DeeplinkTarget? parseDeeplink(Uri uri) {
  if (!isSozoLink(uri)) return null;
  final segments = deeplinkPath(
    uri,
  ).split('/').where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return null;
  final q = uri.queryParameters;
  final url = q['url']?.trim() ?? '';
  final provider = _nonEmpty(q['provider']);

  switch (segments.first) {
    case 'detail':
      if (url.isEmpty) return null;
      return DeeplinkTarget(
        '/detail',
        extra: DetailArgs(contentUrl: url, provider: provider),
      );
    case 'play':
    case 'player':
      if (url.isEmpty) return null;
      final ep = int.tryParse(q['ep']?.trim() ?? '');
      final t = parseStartSeconds(q['t']);
      return DeeplinkTarget(
        '/detail',
        extra: DetailArgs(
          contentUrl: url,
          provider: provider,
          autoPlay: true,
          startEpisode: ep != null && ep > 0 ? ep : null,
          startPositionMs: t == null ? null : (t * 1000).round(),
        ),
      );
    case 'link':
    case 'pair':
      final code = segments.length > 1 ? segments[1].trim() : '';
      return DeeplinkTarget(
        code.isEmpty
            ? '/link-tv'
            : '/link-tv?code=${Uri.encodeComponent(code)}',
      );
    case 'party':
      final code = segments.length > 1 ? segments[1].trim() : '';
      if (code.isEmpty) return null;
      return DeeplinkTarget('/watch-party', extra: WatchPartyArgs(code: code));
    default:
      return null;
  }
}

/// Seconds from a `t` value, or null when it is missing, malformed or zero.
double? parseStartSeconds(String? raw) {
  final s = raw?.trim().toLowerCase() ?? '';
  if (s.isEmpty) return null;
  double? seconds;
  if (s.contains(':')) {
    final parts = s.split(':').map(int.tryParse).toList();
    if (parts.length > 3 || parts.any((p) => p == null || p < 0)) return null;
    seconds = parts.fold<int>(0, (acc, p) => acc * 60 + p!).toDouble();
  } else if (RegExp(r'[hms]').hasMatch(s)) {
    final m = RegExp(
      r'^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+(?:\.\d+)?)s?)?$',
    ).firstMatch(s);
    if (m == null) return null;
    seconds =
        (int.tryParse(m[1] ?? '') ?? 0) * 3600 +
        (int.tryParse(m[2] ?? '') ?? 0) * 60 +
        (double.tryParse(m[3] ?? '') ?? 0);
  } else {
    seconds = double.tryParse(s);
  }
  if (seconds == null || !seconds.isFinite || seconds <= 0) return null;
  return seconds;
}

/// The public link to a title. With an [episode] or a [position] it becomes a
/// `/play` link that starts there; the player can call this with its own
/// state when it gets a share action.
String buildShareLink({
  required String contentUrl,
  String? provider,
  int? episode,
  Duration? position,
}) {
  final params = <String, String>{'url': contentUrl};
  final p = provider?.trim() ?? '';
  if (p.isNotEmpty) params['provider'] = p;
  final ep = episode != null && episode > 0 ? episode : null;
  final t = position == null ? 0 : position.inSeconds;
  if (ep != null) params['ep'] = '$ep';
  if (t > 0) params['t'] = '$t';
  final path = ep != null || t > 0 ? '/play' : '/detail';
  return Uri.https(kDeeplinkHost, path, params).toString();
}

String? _nonEmpty(String? s) {
  final t = s?.trim();
  return t == null || t.isEmpty ? null : t;
}
