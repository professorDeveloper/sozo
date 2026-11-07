/// A party invite that arrived before the user could join it: signed out, or
/// still in first-run setup. Kept through sign-in or sign-up, then opened once.
///
/// Stored as `CODE|savedAtMs` through [read]/[write] so it survives the app
/// being killed while the user goes to fetch a password. Old invites expire:
/// opening a room someone shared yesterday, right after an unrelated sign-in,
/// would be a surprise.
class PendingPartyCode {
  PendingPartyCode({
    required this.read,
    required this.write,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final String? Function() read;
  final Future<void> Function(String? value) write;
  final DateTime Function() _clock;

  static const Duration ttl = Duration(hours: 1);

  static final RegExp _shape = RegExp(r'^[A-Z0-9]{4,12}$');

  /// Upper-cased, trimmed, or null when it cannot be a party code.
  static String? normalize(String? raw) {
    final code = raw?.trim().toUpperCase() ?? '';
    return _shape.hasMatch(code) ? code : null;
  }

  Future<void> remember(String? code) async {
    final c = normalize(code);
    if (c == null) return;
    await write('$c|${_clock().millisecondsSinceEpoch}');
  }

  /// The pending code if there is a fresh one, without clearing it.
  String? peek() {
    final raw = read();
    if (raw == null || raw.isEmpty) return null;
    final bar = raw.indexOf('|');
    final code = normalize(bar < 0 ? raw : raw.substring(0, bar));
    final savedAt = bar < 0 ? null : int.tryParse(raw.substring(bar + 1));
    if (code == null || savedAt == null) return null;
    final age = _clock().difference(
      DateTime.fromMillisecondsSinceEpoch(savedAt),
    );
    if (age.isNegative || age > ttl) return null;
    return code;
  }

  /// The pending code, cleared so it opens once.
  Future<String?> take() async {
    final code = peek();
    if (read() != null) await write(null);
    return code;
  }

  Future<void> clear() => write(null);
}
