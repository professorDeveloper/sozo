import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';


import 'discord_activity.dart';

/// Talks to the Discord desktop client over its local IPC socket.
///
/// ## Why this transport, on desktop
///
/// This is the mechanism Discord publishes for exactly this purpose. The
/// desktop client opens a socket on the machine; an app connects to it, says
/// which application it is, and sends activity. **No token, no login, nothing
/// belonging to the account leaves the machine** — Discord itself is already
/// signed in and does the talking.
///
/// It only works where the Discord desktop client is running, which is why
/// mobile needs the other transport.
///
/// ## The wire format
///
/// Every message is a 4-byte little-endian opcode, a 4-byte little-endian
/// payload length, then UTF-8 JSON. There is no delimiter and no framing
/// beyond that, so a partial read has to be buffered until the declared length
/// arrives — a reply larger than one TCP segment is ordinary, not exceptional.
class DiscordIpcClient {
  DiscordIpcClient({required this.clientId});

  /// The Discord application id, from the developer portal. Also what decides
  /// which uploaded art the asset keys resolve against.
  final String clientId;

  static const int _opHandshake = 0;
  static const int _opFrame = 1;
  static const int _opClose = 2;
  static const int _opPing = 3;
  static const int _opPong = 4;

  Socket? _socket;
  RandomAccessFile? _pipe;
  StreamSubscription<Uint8List>? _sub;
  final BytesBuilder _inbox = BytesBuilder(copy: false);
  bool _connected = false;
  int _nonce = 0;

  bool get isConnected => _connected;

  /// Connects to whichever socket the local Discord client is listening on.
  ///
  /// Discord numbers them 0..9 and uses the first free one, so a machine
  /// running Discord and Discord PTB has two. Trying them in order is what the
  /// official libraries do; there is no discovery beyond it.
  Future<bool> connect() async {
    if (_connected) return true;
    for (var i = 0; i < 10; i++) {
      if (await _tryOne(i)) {
        _connected = true;
        return true;
      }
    }
    return false;
  }

  Future<bool> _tryOne(int index) async {
    try {
      if (Platform.isWindows) {
        // A named pipe, not a socket. Dart has no pipe API, but the pipe is
        // openable as a file and `FileMode.append` is the only mode that asks
        // the OS for read AND write on an existing object.
        final pipe = await File(r'\\.\pipe\discord-ipc-' '$index')
            .open(mode: FileMode.append);
        _pipe = pipe;
      } else {
        final path = _unixCandidates(index).firstWhere(
          (p) => File(p).existsSync() || Link(p).existsSync(),
          orElse: () => '',
        );
        if (path.isEmpty) return false;
        final socket = await Socket.connect(
          InternetAddress(path, type: InternetAddressType.unix),
          0,
          timeout: const Duration(seconds: 2),
        );
        _socket = socket;
        _sub = socket.listen(
          _onBytes,
          onDone: _onDropped,
          onError: (_) => _onDropped(),
          cancelOnError: true,
        );
      }

      await _send(_opHandshake, {'v': 1, 'client_id': clientId});
      return true;
    } catch (_) {
      await _closeQuietly();
      return false;
    }
  }

  /// Every directory a Discord socket is known to appear in.
  ///
  /// The plain temp directory covers a normal install. The three suffixed ones
  /// cover Flatpak, Snap and the Discord flatpak specifically, which sandbox
  /// the socket into a subdirectory — a Linux user on Flatpak Discord has it
  /// nowhere else, and omitting them is why "it works on my machine" reports
  /// happen for this feature.
  List<String> _unixCandidates(int index) {
    final env = Platform.environment;
    final roots = <String>[
      if ((env['XDG_RUNTIME_DIR'] ?? '').isNotEmpty) env['XDG_RUNTIME_DIR']!,
      if ((env['TMPDIR'] ?? '').isNotEmpty) env['TMPDIR']!,
      if ((env['TMP'] ?? '').isNotEmpty) env['TMP']!,
      if ((env['TEMP'] ?? '').isNotEmpty) env['TEMP']!,
      '/tmp',
    ];
    const nested = ['', '/app/com.discordapp.Discord', '/snap.discord', '/app/com.discordapp.DiscordCanary'];
    return [
      for (final root in roots)
        for (final dir in nested)
          '${root.replaceAll(RegExp(r'/$'), '')}$dir/discord-ipc-$index',
    ];
  }

  /// Sets the activity, or clears it when [activity] is null.
  Future<void> setActivity(DiscordActivity? activity) async {
    if (!_connected) return;
    await _send(_opFrame, {
      'cmd': 'SET_ACTIVITY',
      'nonce': '${_nonce++}',
      'args': {
        // Discord ties the activity to a process, and clears it when that
        // process goes away — which is the behaviour we want if the app is
        // killed without a clean disconnect.
        'pid': pid,
        'activity': activity == null ? null : _encode(activity),
      },
    });
  }

  /// The asset key uploaded under the Discord application, shown when the
  /// title has no poster of its own.
  ///
  /// Upload an image named exactly this at
  /// Developer Portal > your application > Rich Presence > Art Assets.
  static const String fallbackAssetKey = 'sozo';

  Map<String, dynamic> _encode(DiscordActivity a) {
    final assets = <String, dynamic>{};
    // A raw https url, not an uploaded asset key.
    //
    // Discord's RPC field historically took only a key of an image uploaded to
    // the developer portal, which cannot work for artwork that differs per
    // title. Current clients resolve an external url here as well — but that
    // support arrived recently enough that an older desktop client may show no
    // art rather than the poster. If that happens, the text lines and the
    // timings are unaffected; only the image is, and [fallbackAssetKey] is
    // what it falls back to.
    if (a.imageUrl != null && a.imageUrl!.isNotEmpty) {
      assets['large_image'] = a.imageUrl;
      if (a.imageText != null) assets['large_text'] = a.imageText;
    } else {
      assets['large_image'] = fallbackAssetKey;
      assets['large_text'] = 'Sozo';
    }
    return {
      // 3 is "Watching". Discord renders it as "Watching <name>" rather than
      // "Playing", which is what this actually is.
      'type': 3,
      'details': a.title,
      if (a.subtitle != null && a.subtitle!.isNotEmpty) 'state': a.subtitle,
      if (assets.isNotEmpty) 'assets': assets,
      'timestamps': {
        if (a.startedAt != null) 'start': a.startedAt!.millisecondsSinceEpoch,
        if (a.endsAt != null) 'end': a.endsAt!.millisecondsSinceEpoch,
      },
      if (a.watchUrl != null && a.watchUrl!.isNotEmpty)
        'buttons': [
          {'label': 'Sozo', 'url': a.watchUrl},
        ],
    };
  }

  Future<void> _send(int op, Map<String, dynamic> payload) async {
    final body = utf8.encode(jsonEncode(payload));
    final header = ByteData(8)
      ..setUint32(0, op, Endian.little)
      ..setUint32(4, body.length, Endian.little);
    final frame = Uint8List(8 + body.length)
      ..setRange(0, 8, header.buffer.asUint8List())
      ..setRange(8, 8 + body.length, body);

    final socket = _socket;
    if (socket != null) {
      socket.add(frame);
      await socket.flush();
      return;
    }
    await _pipe?.writeFrom(frame);
  }

  void _onBytes(Uint8List chunk) {
    _inbox.add(chunk);
    // Frames are consumed only once fully arrived. Discord's replies to
    // SET_ACTIVITY are otherwise routinely split, and a half-read header reads
    // as a nonsense length.
    while (true) {
      final buffered = _inbox.toBytes();
      if (buffered.length < 8) {
        _inbox
          ..clear()
          ..add(buffered);
        return;
      }
      final view = ByteData.sublistView(buffered);
      final op = view.getUint32(0, Endian.little);
      final length = view.getUint32(4, Endian.little);
      if (buffered.length < 8 + length) {
        _inbox
          ..clear()
          ..add(buffered);
        return;
      }
      final rest = buffered.sublist(8 + length);
      _inbox
        ..clear()
        ..add(rest);

      // A ping must be answered or the client drops the connection; the
      // replies to our own frames carry nothing worth acting on.
      if (op == _opPing) {
        unawaited(_send(_opPong, const {}));
      } else if (op == _opClose) {
        _onDropped();
        return;
      }
    }
  }

  void _onDropped() {
    _connected = false;
    unawaited(_closeQuietly());
  }

  Future<void> _closeQuietly() async {
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
    try {
      await _pipe?.close();
    } catch (_) {}
    _pipe = null;
    _inbox.clear();
  }

  Future<void> dispose() async {
    if (_connected) {
      try {
        await setActivity(null);
      } catch (_) {}
    }
    _connected = false;
    await _closeQuietly();
  }
}
