import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:soplay/core/player/shader_presets.dart';

/// Fetches and keeps the Anime4K shader files on disk.
///
/// ## Why a store and not a download call
///
/// mpv needs real paths on disk, so the files have to exist before playback
/// starts, and they have to survive between sessions or every episode pays for
/// the download again. A chain is three files and up to about 300 KB at the
/// high tier — cheap once, absurd per episode.
///
/// ## Failure is "no shaders", never "no playback"
///
/// Every path here returns rather than throws. Somebody who turns this on with
/// no connection should get an unenhanced picture, which is the picture they
/// had yesterday — not an episode that will not start. That is also why
/// [ensure] is asked BEFORE the chain is handed to mpv: a half-downloaded chain
/// passed to `glsl-shaders` makes mpv fail to initialise video output, which
/// presents as a black screen rather than as a missing enhancement.
class ShaderStore {
  ShaderStore({Dio? dio}) : _dio = dio ?? Dio();

  /// The project's own repository. Pinned to a tag rather than a branch so a
  /// rewrite upstream cannot silently change what this app runs on the GPU.
  static const String _base =
      'https://raw.githubusercontent.com/bloc97/Anime4K/v4.0.1/glsl';

  /// Generous, because these are fetched once on a connection that may be bad,
  /// and the alternative to waiting is doing without.
  static const Duration _timeout = Duration(seconds: 45);

  /// A shader smaller than this did not download — it is a 404 body or a
  /// captive-portal page. Writing it would hand mpv a file that fails to
  /// compile, and a failed compile takes video output down with it.
  static const int _minPlausibleBytes = 512;

  final Dio _dio;
  Directory? _dir;

  Future<Directory> _directory() async {
    final cached = _dir;
    if (cached != null) return cached;
    final support = await getApplicationSupportDirectory();
    // Support, not cache: the OS may clear a cache directory at any time, and
    // finding the chain gone mid-episode would drop video output rather than
    // the enhancement.
    final dir = Directory('${support.path}/shaders');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _dir = dir;
  }

  /// Local path for one shader, whether or not it has been fetched.
  Future<String> pathFor(String remote) async {
    final dir = await _directory();
    // Flattened: mpv takes a list of paths and the upstream folder names carry
    // a '+' that has no business in a shell-adjacent property string.
    return '${dir.path}/${remote.split('/').last}';
  }

  Future<bool> isCached(String remote) async =>
      File(await pathFor(remote)).existsSync();

  /// Ensures every file [preset] needs at [tier] is on disk.
  ///
  /// Returns the paths in chain order, or null when any of them could not be
  /// fetched — null rather than a partial list, because a chain missing a link
  /// is not a weaker chain, it is a broken one.
  Future<List<String>?> ensure(ShaderPreset preset, ShaderTier tier) async {
    if (preset.isOff) return const [];
    final wanted = preset.chainFor(tier.id);
    if (wanted.isEmpty) return const [];

    final paths = <String>[];
    for (final remote in wanted) {
      final path = await pathFor(remote);
      final file = File(path);
      if (file.existsSync() && await file.length() >= _minPlausibleBytes) {
        paths.add(path);
        continue;
      }
      if (!await _download(remote, file)) return null;
      paths.add(path);
    }
    return paths;
  }

  Future<bool> _download(String remote, File into) async {
    try {
      final response = await _dio.get<List<int>>(
        '$_base/${Uri.encodeComponent(remote).replaceAll('%2F', '/')}',
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: _timeout,
          sendTimeout: _timeout,
          // Anything but a real 200 is not a shader.
          validateStatus: (s) => s == 200,
        ),
      );
      final bytes = response.data;
      if (bytes == null || bytes.length < _minPlausibleBytes) {
        debugPrint('[shaders] $remote came back too small (${bytes?.length})');
        return false;
      }
      // Written to a temporary name and renamed, so a download interrupted
      // half way cannot leave a truncated file that looks cached forever.
      final tmp = File('${into.path}.part');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(into.path);
      return true;
    } catch (e) {
      debugPrint('[shaders] $remote failed: $e');
      return false;
    }
  }

  /// Total bytes on disk, for the settings row that offers to clear them.
  Future<int> cachedBytes() async {
    try {
      final dir = await _directory();
      var total = 0;
      for (final f in dir.listSync().whereType<File>()) {
        total += await f.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<void> clear() async {
    try {
      final dir = await _directory();
      for (final f in dir.listSync().whereType<File>()) {
        f.deleteSync();
      }
    } catch (e) {
      debugPrint('[shaders] clear failed: $e');
    }
  }
}
