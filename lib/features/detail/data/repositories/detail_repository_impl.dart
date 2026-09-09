import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/manga/manga_channel.dart';
import 'package:soplay/features/extensions/data/mangayomi_bridge.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/js/js_runtime_service.dart';
import 'package:soplay/features/manga/data/models/manga_pages_model.dart';
import 'package:soplay/features/manga/domain/entities/manga_pages_entity.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/detail/data/datasources/detail_data_source.dart';
import 'package:soplay/features/detail/data/models/detail_model.dart';
import 'package:soplay/features/detail/data/models/media_resolve_model.dart';
import 'package:soplay/features/detail/data/models/playback_model.dart';
import 'package:soplay/features/detail/domain/entities/detail_entity.dart';
import 'package:soplay/features/detail/domain/entities/media_resolve_entity.dart';
import 'package:soplay/features/detail/domain/entities/playback_entity.dart';
import 'package:soplay/features/detail/domain/repositories/detail_repository.dart';

class DetailRepositoryImpl implements DetailRepository {
  final DetailDataSource dataSource;
  final JsRuntimeService? jsRuntime;
  final HiveService? hive;

  const DetailRepositoryImpl(
    this.dataSource, {
    required this.mangayomi,
    this.jsRuntime,
    this.hive,
  });

  final MangayomiBridge mangayomi;

  String? _resolveProvider(String? provider) {
    if (provider != null && provider.isNotEmpty) return provider;
    final fromHive = hive?.getCurrentProvider();
    if (fromHive != null && fromHive.isNotEmpty) return fromHive;
    return null;
  }

  @override
  Future<Result<DetailEntity>> getDetail(String contentUrl, {String? provider}) async {
    final js = jsRuntime;
    final effective = _resolveProvider(provider);
    if (effective != null && effective.startsWith('cs:')) {
      try {
        final map = await CloudStreamChannel.load(effective.substring(3), contentUrl);
        if (map.isNotEmpty) return Success(DetailModel.fromJson(map));
        return Failure(Exception('CloudStream: details not found'));
      } catch (e) {
        return Failure(Exception(_normalizeJsError(e)));
      }
    }
    if (effective != null && effective.startsWith('an:')) {
      try {
        final map = await AniyomiChannel.load(effective.substring(3), contentUrl);
        if (map.isNotEmpty) return Success(DetailModel.fromJson(map));
        return Failure(Exception('Aniyomi: details not found'));
      } catch (e) {
        return Failure(Exception(_normalizeJsError(e)));
      }
    }
    if (effective != null && effective.startsWith('mn:')) {
      try {
        final map = await MangaChannel.load(effective.substring(3), contentUrl);
        if (map.isNotEmpty) return Success(DetailModel.fromJson(map));
        return Failure(Exception('Manga: details not found'));
      } catch (e) {
        return Failure(Exception(_normalizeJsError(e)));
      }
    }
    if (effective != null && effective.startsWith('my:')) {
      try {
        final map = await mangayomi.load(effective.substring(3), contentUrl);
        if (map.isNotEmpty) return Success(DetailModel.fromJson(map));
        return Failure(Exception('Mangayomi: details not found'));
      } catch (e) {
        return Failure(Exception(_normalizeJsError(e)));
      }
    }
    if (js != null && effective != null) {
      try {
        final map = await js.tryGetDetail(effective, contentUrl);
        if (map != null) return Success(DetailModel.fromJson(map));
      } catch (e) {
        return Failure(Exception(_normalizeJsError(e)));
      }
    }
    try {
      return Success(await dataSource.getDetail(contentUrl, provider: effective));
    } on DioException catch (e) {
      return Failure(Exception(_messageFrom(e)));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  /// Maps an on-device host's `load()` payload to a playback result.
  ///
  /// The hosts set an `error` field when they produced a page but nothing
  /// playable — a Live TV response type they don't map, a torrent entry with
  /// neither a magnet nor a .torrent url, a source whose apk failed to link.
  /// (Torrent entries that *do* carry a link are playable now: the app embeds a
  /// torrent server.) Without reading it the caller just sees an
  /// empty episode list and shows a generic "no episodes", which is
  /// indistinguishable from a title that genuinely has none.
  Result<PlaybackModel> _playbackFrom(
    Map<String, dynamic> map,
    String label,
    String sort,
  ) {
    if (map.isEmpty) return Failure(Exception('$label: source unavailable'));
    final model = PlaybackModel.fromJson(map);
    if (model.episodes.isEmpty) {
      final err = map['error'];
      return Failure(Exception(
        err is String && err.isNotEmpty ? '$label: $err' : '$label: nothing to play',
      ));
    }
    return Success(_applySort(model, sort));
  }

  @override
  Future<Result<PlaybackEntity>> getEpisodes(
    String contentUrl, {
    int page = 1,
    int size = 100,
    String sort = 'asc',
    String? provider,
  }) async {
    final js = jsRuntime;
    final effective = _resolveProvider(provider);
    if (effective != null && effective.startsWith('cs:')) {
      try {
        final map = await CloudStreamChannel.load(effective.substring(3), contentUrl);
        return _playbackFrom(map, 'CloudStream', sort);
      } catch (e) {
        return Failure(Exception(_normalizeJsError(e)));
      }
    }
    if (effective != null && effective.startsWith('an:')) {
      try {
        final map = await AniyomiChannel.load(effective.substring(3), contentUrl);
        return _playbackFrom(map, 'Aniyomi', sort);
      } catch (e) {
        return Failure(Exception(_normalizeJsError(e)));
      }
    }
    if (effective != null && effective.startsWith('mn:')) {
      try {
        final map = await MangaChannel.load(effective.substring(3), contentUrl);
        return _playbackFrom(map, 'Manga', sort);
      } catch (e) {
        return Failure(Exception(_normalizeJsError(e)));
      }
    }
    if (effective != null && effective.startsWith('my:')) {
      try {
        final map = await mangayomi.load(effective.substring(3), contentUrl);
        return _playbackFrom(map, 'Mangayomi', sort);
      } catch (e) {
        return Failure(Exception(_normalizeJsError(e)));
      }
    }
    if (js != null && effective != null) {
      try {
        final map = await js.tryGetEpisodes(effective, contentUrl);
        if (map != null) {
          return Success(_applySort(PlaybackModel.fromJson(map), sort));
        }
      } catch (e) {
        return Failure(Exception(_normalizeJsError(e)));
      }
    }
    try {
      return Success(
        await dataSource.getEpisodes(
          contentUrl,
          page: page,
          size: size,
          sort: sort,
          provider: effective,
        ),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 501) {
        return Failure(
          Exception('Provider epizodlarni qo\'llab-quvvatlamaydi'),
        );
      }
      return Failure(Exception(_messageFrom(e)));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<MediaResolveEntity>> resolveMedia({
    required String ref,
    required String provider,
    String? lang,
  }) async {
    if (provider.startsWith('cs:')) {
      try {
        final map = await CloudStreamChannel.loadLinks(provider.substring(3), ref);
        final sources = map['videoSources'];
        if (map.isNotEmpty && sources is List && sources.isNotEmpty) {
          return _postProcess(MediaResolveModel.fromJson(map));
        }
        return Failure(Exception('CloudStream: stream not found'));
      } catch (e) {
        if (kDebugMode) debugPrint('[resolveMedia] CloudStream path failed: $e');
        return Failure(Exception(_normalizeJsError(e)));
      }
    }
    if (provider.startsWith('an:')) {
      try {
        final map = await AniyomiChannel.loadLinks(provider.substring(3), ref);
        final sources = map['videoSources'];
        if (map.isNotEmpty && sources is List && sources.isNotEmpty) {
          return _postProcess(MediaResolveModel.fromJson(map));
        }
        return Failure(Exception('Aniyomi: stream not found'));
      } catch (e) {
        if (kDebugMode) debugPrint('[resolveMedia] Aniyomi path failed: $e');
        return Failure(Exception(_normalizeJsError(e)));
      }
    }
    if (provider.startsWith('my:')) {
      try {
        final map = await mangayomi.loadLinks(provider.substring(3), ref);
        final sources = map['videoSources'];
        if (map.isNotEmpty && sources is List && sources.isNotEmpty) {
          return _postProcess(MediaResolveModel.fromJson(map));
        }
        return Failure(Exception('Mangayomi: stream not found'));
      } catch (e) {
        if (kDebugMode) debugPrint('[resolveMedia] Mangayomi path failed: $e');
        return Failure(Exception(_normalizeJsError(e)));
      }
    }
    final js = jsRuntime;
    if (js != null) {
      try {
        final map = await js.tryResolveMedia(
          provider: provider,
          ref: ref,
          lang: lang,
        );
        if (map != null) {
          return _postProcess(MediaResolveModel.fromJson(map));
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[resolveMedia] JS path failed: $e');
        return Failure(Exception(_normalizeJsError(e)));
      }
    }

    try {
      return _postProcess(
        await dataSource.resolveMedia(
          ref: ref,
          provider: provider,
          lang: lang,
        ),
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 422) {
        return Failure(Exception('Video URL aniqlanmadi'));
      }
      if (code == 501) {
        return Failure(
          Exception('Provider media yechishni qo\'llab-quvvatlamaydi'),
        );
      }
      return Failure(Exception(_messageFrom(e)));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<MangaPagesEntity>> getPages({
    required String ref,
    required String provider,
  }) async {
    if (provider.startsWith('mn:')) {
      try {
        final map = await MangaChannel.pageList(provider.substring(3), ref);
        final pages = map['pages'];
        if (map.isNotEmpty && pages is List && pages.isNotEmpty) {
          return Success(MangaPagesModel.fromJson(map));
        }
        return Failure(Exception('Manga: sahifalar topilmadi'));
      } catch (e) {
        return Failure(Exception(_normalizeJsError(e)));
      }
    }
    if (provider.startsWith('my:')) {
      try {
        final map = await mangayomi.pageList(provider.substring(3), ref);
        final pages = map['pages'];
        if (map.isNotEmpty && pages is List && pages.isNotEmpty) {
          return Success(MangaPagesModel.fromJson(map));
        }
        return Failure(Exception('Mangayomi: sahifalar topilmadi'));
      } catch (e) {
        return Failure(Exception(_normalizeJsError(e)));
      }
    }
    return Failure(Exception('Sahifalar faqat manga manbalari uchun'));
  }

  Future<Result<MediaResolveEntity>> _postProcess(
    MediaResolveEntity media,
  ) async {
    return Success(media);
  }

  PlaybackModel _applySort(PlaybackModel model, String sort) {
    // Sorts IN PLACE, so it can only run on a list we know is growable. Models
    // built from a const/unmodifiable `episodes` would otherwise throw
    // "Cannot modify an unmodifiable list" here rather than at construction,
    // far from the cause.
    // Copy before sorting: `sort` mutates in place and throws
    // "Cannot modify an unmodifiable list" on a const/fixed-length list, which
    // several of the host adapters can legitimately produce.
    final eps = model.episodes.toList();
    if (eps.length < 2) return model;
    final desc = sort.toLowerCase() == 'desc';
    final orig = Map<Object?, int>.identity();
    for (var i = 0; i < eps.length; i++) {
      orig[eps[i]] = i;
    }
    eps.sort((a, b) {
      var c = a.episode.compareTo(b.episode);
      if (c == 0) c = (orig[a] ?? 0).compareTo(orig[b] ?? 0);
      return desc ? -c : c;
    });
    return model.copyWithEpisodes(eps);
  }

  String _normalizeJsError(Object error) {
    final raw = error.toString();
    if (raw.contains('no playable source')) return 'Video manbasi topilmadi';
    if (raw.contains('Invalid mediaRef')) {
      return 'Provider versiyasi eskirgan';
    }
    if (raw.contains('No servers found')) return 'Episode uchun server yo\'q';
    return raw.replaceFirst('Exception: ', '');
  }

  String _messageFrom(DioException e) {
    // e.response?.data is dynamic and is a raw String for non-JSON error bodies
    // (502/503 HTML, Cloudflare challenge, plain text). A forced `as Map` would
    // throw a TypeError from inside the catch clause — which the sibling
    // `catch (e)` cannot catch — hanging the screen on its loading state.
    final data = e.response?.data;
    final msg = data is Map ? data['message'] : null;
    return (msg is String && msg.isNotEmpty)
        ? msg
        : (e.message ?? 'Xatolik yuz berdi');
  }
}
