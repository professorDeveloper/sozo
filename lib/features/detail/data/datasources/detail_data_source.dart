import 'package:dio/dio.dart';
import 'package:soplay/features/detail/data/models/detail_model.dart';
import 'package:soplay/features/detail/data/models/media_resolve_model.dart';
import 'package:soplay/features/detail/data/models/playback_model.dart';

class DetailDataSource {
  final Dio dio;
  const DetailDataSource({required this.dio});

  Future<DetailModel> getDetail(String contentUrl, {String? provider}) async {
    final response = await dio.get(
      '/contents/detail',
      queryParameters: {
        'url': contentUrl,
        if (provider != null && provider.isNotEmpty) 'provider': provider,
      },
    );
    return DetailModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// A catalogue's own record of a title, with `extra.about` alongside the
  /// usual detail. Only TMDB is served this way; AniList answers the device
  /// directly.
  Future<Map<String, dynamic>> getCatalogueDetail(
    String kind,
    String contentUrl,
  ) async {
    final response = await dio.get(
      '/catalogue/$kind/detail',
      queryParameters: {'url': contentUrl},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<PlaybackModel> getEpisodes(
    String contentUrl, {
    int page = 1,
    int size = 100,
    String sort = 'asc',
    String? provider,
  }) async {
    final response = await dio.get(
      '/contents/episodes',
      queryParameters: {
        'url': contentUrl,
        'page': page,
        'size': size,
        'sort': sort,
        if (provider != null && provider.isNotEmpty) 'provider': provider,
      },
    );
    return PlaybackModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<MediaResolveModel> resolveMedia({
    required String ref,
    required String provider,
    String? lang,
  }) async {
    final response = await dio.get(
      '/contents/media',
      queryParameters: {
        'ref': ref,
        'provider': provider,
        if (lang != null && lang.isNotEmpty) 'lang': lang,
      },
    );
    return MediaResolveModel.fromJson(response.data as Map<String, dynamic>);
  }
}
