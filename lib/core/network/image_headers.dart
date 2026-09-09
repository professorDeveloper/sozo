import 'package:soplay/core/network/user_agent.dart';

/// Headers a poster request needs to get past the host that serves it.
///
/// Lifted out of `HomeNetworkImage` so the hero shuttle and the detail header
/// can send the same ones. They have to be identical, not merely similar:
/// `CachedNetworkImageProvider` folds the headers into nothing, but the
/// upstream host does not — a request without the Referer is refused, and a
/// request under a different agent is challenged, because a `cf_clearance`
/// cookie is bound to the exact agent that earned it. Two call sites drawing
/// the same poster with different headers is one call site drawing a grey box.
Map<String, String>? posterImageHeaders(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  return {
    'Referer': '${uri.scheme}://${uri.host}/',
    'User-Agent': kSozoUserAgent,
  };
}
