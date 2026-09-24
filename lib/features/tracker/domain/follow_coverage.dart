import 'package:soplay/features/tracker/domain/entities/followed_title.dart';

/// Who announces a new episode: the server or this device.
///
/// The server checks what it can reach itself: its own providers, AniList
/// anime and TMDB shows. Extension hosts (`cs:`, `an:`, `mn:`, `my:`) and
/// Jellyfin run on the phone and nowhere else, films never get episodes, and
/// the AniList manga and novel shelves carry no chapter list anyone can read.
class FollowCoverage {
  const FollowCoverage._();

  static const List<String> devicePrefixes = ['cs:', 'an:', 'mn:', 'my:', 'jf:'];

  static bool isExtension(String provider) => devicePrefixes.any(provider.startsWith);

  static bool isCatalogue(String provider) => provider.startsWith('cat:');

  static bool _isAnilistAnime(FollowedTitle t) {
    if (t.provider == 'cat:anilist') return true;
    final uri = Uri.tryParse(t.contentUrl);
    final host = uri?.host.toLowerCase() ?? '';
    return (host == 'anilist.co' || host.endsWith('.anilist.co')) &&
        (uri?.pathSegments.firstOrNull == 'anime');
  }

  static bool _isTmdbShow(FollowedTitle t) {
    final host = Uri.tryParse(t.contentUrl)?.host.toLowerCase() ?? '';
    final tmdb = t.provider == 'cat:tmdb' ||
        host == 'themoviedb.org' ||
        host.endsWith('.themoviedb.org');
    return tmdb && t.tmdbKind == 'tv';
  }

  /// Whether the server checks [t] on its own.
  static bool serverCovers(FollowedTitle t) {
    if (t.provider.isEmpty || isExtension(t.provider)) return false;
    if (!isCatalogue(t.provider)) return true;
    return _isAnilistAnime(t) || _isTmdbShow(t);
  }

  /// Whether this device should raise the notification for [t] itself.
  ///
  /// [serverLive] is false until `/follows` has answered once: before then the
  /// server knows nothing and the device must not stay quiet. A title still
  /// waiting in the upload queue is not known to the server either.
  static bool deviceNotifies(
    FollowedTitle t, {
    required bool signedIn,
    required bool serverLive,
    bool pendingUpload = false,
  }) {
    if (!t.notify) return false;
    if (!signedIn || !serverLive || pendingUpload) return true;
    return !serverCovers(t);
  }

  /// Whether the device can read an episode list for [t] at all. A
  /// catalogue page has none — asking one for episodes is a bug.
  static bool deviceCanCheck(FollowedTitle t) =>
      t.provider.isNotEmpty && !isCatalogue(t.provider);

  /// Whether a background check on this device has to look at [t].
  static bool deviceChecks(
    FollowedTitle t, {
    required bool signedIn,
    required bool serverLive,
  }) {
    if (!deviceCanCheck(t)) return false;
    if (!signedIn || !serverLive) return true;
    return !serverCovers(t);
  }
}
