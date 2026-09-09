import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'discord_activity.dart';
import 'discord_gateway_client.dart';
import 'discord_ipc_client.dart';

/// Shows what somebody is watching on their Discord profile.
///
/// ## Two transports, one reason
///
/// Desktop talks to the local Discord client over its published IPC socket —
/// no credentials, nothing leaves the machine. Mobile has no client to talk
/// to, and Discord offers no way for a third party to set a user's presence,
/// so the only mechanism is to connect to the gateway as that user with their
/// own token. See [DiscordGatewayClient] for what that costs and why it is
/// here anyway.
///
/// Both are OFF until switched on. Neither runs without the viewer having
/// chosen it, and on mobile the token has to be supplied by hand as well.
///
/// ## What is deliberately not here
///
/// No retry loop. If Discord is not running, presence is simply not shown —
/// reconnecting on a timer would keep a socket attempt alive for the life of
/// the app to serve a decoration. A connection is attempted when playback
/// starts and abandoned if it fails.
class DiscordPresenceService {
  DiscordPresenceService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// Where the mobile token lives. Nowhere else, and never in Hive — Hive is
  /// unencrypted and ends up in backups.
  static const String _tokenKey = 'discord_user_token';

  /// The Discord application whose uploaded art the desktop asset keys resolve
  /// against. Empty disables desktop presence rather than connecting as
  /// somebody else's application.
  static String get clientId =>
      (dotenv.isInitialized ? dotenv.maybeGet('DISCORD_CLIENT_ID') : null)
          ?.trim() ??
      '';

  DiscordIpcClient? _ipc;
  DiscordGatewayClient? _gateway;
  DiscordActivity? _last;
  Timer? _throttle;
  DiscordActivity? _queued;
  bool _enabled = false;

  /// Discord drops presence updates sent more often than roughly one every
  /// fifteen seconds per connection. A player ticks several times a second, so
  /// updates are coalesced rather than sent.
  static const Duration _minInterval = Duration(seconds: 15);

  bool get isConnected =>
      (_ipc?.isConnected ?? false) || (_gateway?.isConnected ?? false);

  /// What was last published, so a settings screen can show the viewer the
  /// card their friends are seeing rather than describing it.
  DiscordActivity? get currentActivity => _last;

  /// True where presence can work at all without the viewer pasting a token.
  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token.trim());

  /// Disconnects and removes the token.
  ///
  /// Both, always. A "disconnect" that leaves the credential on the device is
  /// the version of this feature nobody would agree to.
  Future<void> forget() async {
    await stop();
    await _storage.delete(key: _tokenKey);
  }

  /// Brings up whichever transport this platform has.
  ///
  /// Returns whether presence is actually live, so a settings screen can say
  /// "connected" only when it is.
  Future<bool> start() async {
    if (_enabled && isConnected) return true;
    _enabled = true;

    if (isDesktop) {
      if (clientId.isEmpty) {
        debugPrint('[discord] no DISCORD_CLIENT_ID; desktop presence is off');
        return false;
      }
      final ipc = DiscordIpcClient(clientId: clientId);
      if (await ipc.connect()) {
        _ipc = ipc;
        return true;
      }
      // Discord is not running. Not an error worth surfacing — the viewer
      // will see "not connected" and that is the whole story.
      await ipc.dispose();
      return false;
    }

    final token = await readToken();
    if (token == null || token.isEmpty) return false;
    final gateway = DiscordGatewayClient(token: token);
    if (await gateway.connect()) {
      _gateway = gateway;
      return true;
    }
    await gateway.dispose();
    return false;
  }

  Future<void> stop() async {
    _enabled = false;
    _throttle?.cancel();
    _throttle = null;
    _queued = null;
    _last = null;
    final ipc = _ipc;
    final gateway = _gateway;
    _ipc = null;
    _gateway = null;
    await ipc?.dispose();
    await gateway?.dispose();
  }

  /// Reports what is playing. Safe to call as often as the player likes.
  void update(DiscordActivity? activity) {
    if (!_enabled) return;

    if (activity == null) {
      _throttle?.cancel();
      _throttle = null;
      _queued = null;
      _last = null;
      unawaited(_push(null));
      return;
    }

    // Position is not part of the comparison: it changes constantly and
    // Discord derives the elapsed bar from the timestamps itself. Only a
    // change the viewer's friends would SEE is worth an update.
    if (activity.sameAs(_last)) return;

    if (_throttle == null) {
      _last = activity;
      unawaited(_push(activity));
      _throttle = Timer(_minInterval, () {
        _throttle = null;
        final queued = _queued;
        _queued = null;
        if (queued != null) update(queued);
      });
      return;
    }
    // Inside the window: keep only the newest. A viewer skipping through four
    // episodes should end on the fourth, not replay all four.
    _queued = activity;
  }

  Future<void> _push(DiscordActivity? activity) async {
    try {
      await _ipc?.setActivity(activity);
      await _gateway?.setActivity(activity);
    } catch (e) {
      debugPrint('[discord] could not set activity: $e');
    }
  }

  Future<void> dispose() => stop();
}
