import 'package:soplay/core/subtitles/subtitle_cipher.dart';

class SubtitleEntity {
  final String label;
  final String file;
  final bool isDefault;
  final Map<String, String> headers;

  /// Set when the file's cue text is encrypted; the loader decrypts it.
  final SubtitleCipher? cipher;

  const SubtitleEntity({
    required this.label,
    required this.file,
    this.isDefault = false,
    this.headers = const {},
    this.cipher,
  });
}
