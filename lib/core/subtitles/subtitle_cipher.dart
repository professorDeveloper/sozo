import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import 'subtitle_parser.dart';

class SubtitleCipherException implements Exception {
  const SubtitleCipherException(this.message);
  final String message;
  @override
  String toString() => 'SubtitleCipherException: $message';
}

/// The key a source sends with a subtitle whose cue text lines are encrypted.
///
/// KissKH's `.srt.txt1` files are ordinary SRT with every text line AES-128-CBC
/// encrypted and base64 encoded. See the backend's `docs/SUBTITLE_CIPHER.md`.
class SubtitleCipher {
  const SubtitleCipher({
    required this.alg,
    required this.key,
    required this.iv,
    this.scope = _scope,
    this.encoding = _encoding,
  });

  static const _alg = 'aes-128-cbc';
  static const _scope = 'cue-text';
  static const _encoding = 'base64';

  final String alg;
  final String key;
  final String iv;
  final String scope;
  final String encoding;

  /// Null unless [raw] is a map with a non-empty `alg`, `key` and `iv`.
  static SubtitleCipher? fromJson(Object? raw) {
    if (raw is! Map) return null;
    String? text(String field) {
      final v = raw[field];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    final alg = text('alg');
    final key = text('key');
    final iv = text('iv');
    if (alg == null || key == null || iv == null) return null;
    return SubtitleCipher(
      alg: alg,
      key: key,
      iv: iv,
      scope: text('scope') ?? _scope,
      encoding: text('encoding') ?? _encoding,
    );
  }

  bool get isSupported =>
      alg.toLowerCase() == _alg &&
      scope.toLowerCase() == _scope &&
      encoding.toLowerCase() == _encoding;

  /// Decrypts a downloaded file and returns it as UTF-8 bytes.
  Future<List<int>> decryptBytes(List<int> bytes) async =>
      utf8.encode(await decrypt(decodeSubtitleBytes(bytes)));

  /// Decrypts every cue text line of [body]; cue numbers, timing lines and
  /// blank lines pass through, and a line that does not open is kept as is.
  ///
  /// Throws when the cipher is unsupported or fewer than half the text lines
  /// open: a wrong key still yields valid padding now and then.
  Future<String> decrypt(String body) async {
    if (!isSupported) {
      throw SubtitleCipherException('unsupported $alg/$scope/$encoding');
    }
    final keyBytes = utf8.encode(key);
    final ivBytes = utf8.encode(iv);
    if (keyBytes.length != 16 || ivBytes.length != 16) {
      throw const SubtitleCipherException('key and iv must be 16 bytes');
    }
    final aes = DartAesCbc.with128bits(macAlgorithm: MacAlgorithm.empty);
    final secret = SecretKeyData(keyBytes);

    var encrypted = 0;
    var opened = 0;
    final out = <String>[];
    for (final line in body.split('\n')) {
      final cr = line.endsWith('\r');
      final text = (cr ? line.substring(0, line.length - 1) : line).trim();
      if (!_isCueText(text)) {
        out.add(line);
        continue;
      }
      encrypted++;
      try {
        final clear = await aes.decrypt(
          SecretBox(base64.decode(text), nonce: ivBytes, mac: Mac.empty),
          secretKey: secret,
        );
        out.add(cr ? '${utf8.decode(clear)}\r' : utf8.decode(clear));
        opened++;
      } catch (_) {
        out.add(line);
      }
    }
    if (encrypted > 0 && opened * 2 < encrypted) {
      throw SubtitleCipherException('opened $opened of $encrypted lines');
    }
    return out.join('\n');
  }

  static bool _isCueText(String text) =>
      text.isNotEmpty &&
      !text.contains('-->') &&
      text != 'WEBVTT' &&
      !RegExp(r'^\d+$').hasMatch(text);
}
