import 'package:soplay/features/detail/data/models/subtitle_model.dart';
import 'package:soplay/features/detail/data/models/thumbnails_model.dart';
import 'package:soplay/features/detail/data/models/video_source_model.dart';
import 'package:soplay/features/detail/domain/entities/extractor_config_entity.dart';
import 'package:soplay/features/detail/domain/entities/media_resolve_entity.dart';

class MediaResolveModel extends MediaResolveEntity {
  const MediaResolveModel({
    required super.videoUrl,
    required super.headers,
    super.type,
    super.videoSources,
    super.languagesAvailable,
    super.activeLang,
    super.subtitles,
    super.thumbnails,
    super.extractor,
  });

  factory MediaResolveModel.fromJson(Map<String, dynamic> json) {
    final typeRaw = json['type'] as String?;
    final sources = (json['videoSources'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(VideoSourceModel.fromJson)
        .toList(growable: false);
    final subs = (json['subtitles'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SubtitleModel.fromJson)
        .toList(growable: false);
    return MediaResolveModel(
      videoUrl: json['videoUrl'] as String? ?? '',
      type: typeRaw == null || typeRaw.isEmpty ? null : typeRaw.toLowerCase(),
      headers: _parseHeaders(json['headers']),
      videoSources: sources,
      languagesAvailable: _parseLangs(json['languagesAvailable']),
      activeLang: _parseActiveLang(json['server']),
      subtitles: subs,
      thumbnails: ThumbnailsModel.fromJson(json['thumbnails']),
      extractor: _parseExtractor(json['extractor']),
    );
  }

  static ExtractorConfigEntity? _parseExtractor(dynamic raw) {
    if (raw is! Map) return null;
    final hostPattern = raw['hostPattern'] as String?;
    if (hostPattern == null || hostPattern.isEmpty) return null;
    final patterns = (raw['urlPatterns'] as List? ?? const [])
        .whereType<String>()
        .toList(growable: false);
    if (patterns.isEmpty) return null;
    final headers = (raw['captureHeaders'] as List? ?? const [])
        .whereType<String>()
        .toList(growable: false);
    final blockHosts = (raw['blockHosts'] as List? ?? const [])
        .whereType<String>()
        .toList(growable: false);
    final timeout = raw['timeoutMs'];
    final loginUrl = raw['loginUrl'] as String?;
    final playType = (raw['playType'] as String?)?.toLowerCase();
    return ExtractorConfigEntity(
      rewrite: _parseRewrite(raw['rewrite']),
      mode: raw['mode'] as String? ?? 'shouldInterceptRequest',
      hostPattern: hostPattern,
      urlPatterns: patterns,
      captureHeaders: headers,
      blockHosts: blockHosts,
      timeoutMs: timeout is num ? timeout.toInt() : 20000,
      loginUrl: loginUrl != null && loginUrl.isNotEmpty ? loginUrl : null,
      playType: playType == null || playType.isEmpty ? 'hls' : playType,
    );
  }

  static UrlRewrite? _parseRewrite(dynamic raw) {
    if (raw is! Map) return null;
    final pattern = raw['pattern'] as String?;
    final replace = raw['replace'] as String?;
    if (pattern == null || pattern.isEmpty || replace == null) return null;
    return UrlRewrite(
      pattern: pattern,
      replace: replace,
      verify: raw['verify'] != false,
    );
  }

  static Map<String, String> _parseHeaders(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    raw.forEach((k, v) {
      if (k is String && v != null) out[k] = v.toString();
    });
    return out;
  }

  static List<String> _parseLangs(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<String>()
        .map((e) => e.toLowerCase())
        .toList(growable: false);
  }

  static String? _parseActiveLang(dynamic server) {
    if (server is! Map) return null;
    final lang = server['lang'];
    return lang is String ? lang.toLowerCase() : null;
  }
}
