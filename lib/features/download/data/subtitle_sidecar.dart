import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:soplay/features/detail/domain/entities/subtitle_entity.dart';

/// Subtitle files kept beside a downloaded episode.
///
/// A download used to be the video and nothing else: offline, the tracks
/// that came with the episode were gone, and the only subtitles were ones
/// that could be searched for — which needs the connection the download was
/// for doing without. The tracks are fetched when the download is started
/// (the player has them, with the headers their host wants) and read back
/// when the file is played.
///
/// Keyed by the download's id, in the app's own support directory rather
/// than next to the video, which may be on shared storage the app cannot
/// list later.
class SubtitleSidecar {
  SubtitleSidecar({Dio? dio, Future<Directory> Function()? root})
    : _dio = dio ?? Dio(),
      _root = root ?? getApplicationSupportDirectory;

  final Dio _dio;
  final Future<Directory> Function() _root;

  /// Enough for every language a source offers, not a mirror of a
  /// subtitle site.
  static const int maxTracks = 8;
  static const int maxBytes = 3 * 1024 * 1024;

  Future<Directory> _dir(String id) async =>
      Directory('${(await _root()).path}/download_subs/$id');

  static String _extensionOf(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    for (final ext in const ['vtt', 'srt', 'ass', 'ssa', 'ttml', 'dfxp']) {
      if (path.endsWith('.$ext')) return ext;
    }
    return 'sub';
  }

  /// Fetches [tracks] for download [id] — the one being watched first, so it
  /// is the one switched on offline. Tracks held only in memory (AI) or on
  /// this device already are copied as they are. Returns how many were kept.
  Future<int> save(
    String id,
    List<SubtitleEntity> tracks, {
    int active = -1,
  }) async {
    final ordered = <SubtitleEntity>[
      if (active >= 0 && active < tracks.length) tracks[active],
      for (var i = 0; i < tracks.length; i++)
        if (i != active) tracks[i],
    ];
    final dir = await _dir(id);
    final kept = <Map<String, dynamic>>[];
    for (final t in ordered) {
      if (kept.length >= maxTracks) break;
      try {
        List<int>? bytes;
        if (t.file.startsWith('http')) {
          final res = await _dio.get<List<int>>(
            t.file,
            options: Options(
              responseType: ResponseType.bytes,
              headers: t.headers.isEmpty ? null : t.headers,
              receiveTimeout: const Duration(seconds: 20),
              validateStatus: (s) => s != null && s >= 200 && s < 300,
            ),
          );
          bytes = res.data;
        } else if (!t.file.startsWith('ai:') && File(t.file).existsSync()) {
          bytes = await File(t.file).readAsBytes();
        }
        if (bytes == null || bytes.isEmpty || bytes.length > maxBytes) {
          continue;
        }
        if (!await dir.exists()) await dir.create(recursive: true);
        final name = '${kept.length}.${_extensionOf(t.file)}';
        await File('${dir.path}/$name').writeAsBytes(bytes, flush: true);
        kept.add({'label': t.label, 'file': name});
      } catch (e) {
        debugPrint('subtitle sidecar: ${t.label}: $e');
      }
    }
    if (kept.isNotEmpty) {
      await File(
        '${dir.path}/manifest.json',
      ).writeAsString(jsonEncode(kept), flush: true);
    }
    return kept.length;
  }

  /// The tracks kept for [id], as files on this device; empty when none.
  Future<List<SubtitleEntity>> load(String id) async {
    try {
      final dir = await _dir(id);
      final manifest = File('${dir.path}/manifest.json');
      if (!await manifest.exists()) return const [];
      final rows = jsonDecode(await manifest.readAsString());
      if (rows is! List) return const [];
      return [
        for (final (i, r) in rows.indexed)
          if (r is Map && File('${dir.path}/${r['file']}').existsSync())
            SubtitleEntity(
              label: '${r['label'] ?? 'Subtitle'}',
              file: '${dir.path}/${r['file']}',
              isDefault: i == 0,
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> delete(String id) async {
    try {
      final dir = await _dir(id);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }
}
