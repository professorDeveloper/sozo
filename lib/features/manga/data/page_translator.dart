import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:soplay/core/subtitles/subtitle_translation_service.dart';
import 'package:soplay/features/manga/domain/entities/manga_page_entity.dart';
import 'package:soplay/features/manga/domain/translate/page_translation.dart';

/// Reads the lettering off a manga page on the device and has the backend
/// translate it, one request per page.
///
/// Android and iOS only: ML Kit has no desktop build. [isSupported] is what
/// the reader branches on before showing anything.
class PageTranslator {
  PageTranslator({SubtitleTranslationService service =
      const SubtitleTranslationService()})
    : _service = service;

  final SubtitleTranslationService _service;
  TextRecognizer? _recognizer;

  /// The real host, not [defaultTargetPlatform]: widget tests report Android
  /// there and have no ML Kit.
  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// A translation made before, from disk. Costs nothing.
  Future<PageTranslation?> cached({
    required String chapterUrl,
    required int pageIndex,
    required String targetLang,
  }) async {
    try {
      final file = await _cacheFile(chapterUrl, pageIndex, targetLang);
      if (!await file.exists()) return null;
      return PageTranslation.tryFromJson(jsonDecode(await file.readAsString()));
    } catch (_) {
      return null;
    }
  }

  /// Recognises, merges and translates [page]. Throws [PageTranslateException].
  Future<PageTranslation> translate({
    required MangaPageEntity page,
    required Map<String, String> headers,
    required String chapterUrl,
    required int pageIndex,
    required String targetLang,
  }) async {
    final path = await _imagePath(page, headers);
    final size = await _imageSize(path);

    final recognizer = _recognizer ??= TextRecognizer(
      script: TextRecognitionScript.latin,
    );
    final RecognizedText found;
    try {
      found = await recognizer.processImage(InputImage.fromFilePath(path));
    } catch (e) {
      throw PageTranslateException(PageTranslateFailure.failed, '$e');
    }

    final blocks = mergeBlocks([
      for (final b in found.blocks)
        OcrBlock(
          rect: b.boundingBox,
          text: b.lines.map((l) => l.text).join('\n'),
          lineHeight: b.lines.isEmpty
              ? b.boundingBox.height
              : b.boundingBox.height / b.lines.length,
        ),
    ]);
    final texts = [for (final b in blocks) normalizeOcrText(b.text)];
    if (texts.every((t) => t.isEmpty)) {
      throw const PageTranslateException(PageTranslateFailure.noText);
    }

    final List<String> out;
    try {
      out = await _service.translateLines(
        lines: texts,
        targetLang: targetLang,
        docKey: pageTranslateDocKey(chapterUrl, pageIndex),
        count: true,
      );
    } on SubtitleDailyLimitReached catch (e) {
      throw PageTranslateException(PageTranslateFailure.dailyLimit, e.message);
    } on TranslationOffline {
      throw const PageTranslateException(PageTranslateFailure.offline);
    } on TranslationNeedsSignIn {
      throw const PageTranslateException(PageTranslateFailure.signIn);
    } catch (e) {
      throw PageTranslateException(PageTranslateFailure.failed, '$e');
    }

    final translation = PageTranslation(
      imageSize: size,
      targetLang: targetLang,
      blocks: [
        for (var i = 0; i < blocks.length; i++)
          if (texts[i].isNotEmpty)
            TranslatedBlock(rect: blocks[i].rect, source: texts[i], text: out[i]),
      ],
    );
    try {
      final file = await _cacheFile(chapterUrl, pageIndex, targetLang);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(translation.toJson()));
    } catch (_) {}
    return translation;
  }

  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }

  /// The page as a file: a downloaded page already is one, and a network page
  /// is in the image cache once it has been on screen.
  Future<String> _imagePath(
    MangaPageEntity page,
    Map<String, String> headers,
  ) async {
    final url = page.imageUrl;
    if (!url.startsWith('http')) return url;
    final key = page.cacheKey ?? url;
    try {
      final hit = await DefaultCacheManager().getFileFromCache(key);
      if (hit != null) return hit.file.path;
      final cookie = page.cookie;
      final file = await DefaultCacheManager().getSingleFile(
        url,
        key: key,
        headers: {
          ...headers,
          ...page.headers,
          if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
        },
      );
      return file.path;
    } on SocketException {
      throw const PageTranslateException(PageTranslateFailure.offline);
    } catch (e) {
      throw PageTranslateException(PageTranslateFailure.failed, '$e');
    }
  }

  /// Width and height from the file header, without decoding the page.
  Future<ui.Size> _imageSize(String path) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromFilePath(path);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final size = ui.Size(
        descriptor.width.toDouble(),
        descriptor.height.toDouble(),
      );
      descriptor.dispose();
      buffer.dispose();
      return size;
    } catch (e) {
      throw PageTranslateException(PageTranslateFailure.failed, '$e');
    }
  }

  Future<File> _cacheFile(String chapterUrl, int pageIndex, String lang) async {
    final dir = await getApplicationSupportDirectory();
    final name = sha1
        .convert(utf8.encode('$chapterUrl\n$pageIndex\n$lang'))
        .toString();
    return File('${dir.path}/manga_translations/$name.json');
  }
}
