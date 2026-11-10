import 'package:dio/dio.dart';
import 'package:soplay/features/comments/domain/timed_reactions.dart';

class TimedReactionsDataSource {
  const TimedReactionsDataSource({required this.dio});

  final Dio dio;

  Future<ReactionTimeline> fetch({
    required String provider,
    required String contentUrl,
    required String episodeKey,
  }) async {
    final res = await dio.get(
      '/reactions',
      queryParameters: {
        'provider': provider,
        'contentUrl': contentUrl,
        'episodeKey': episodeKey,
      },
    );
    final data = res.data;
    if (data is! Map) return ReactionTimeline.empty;
    return ReactionTimeline.fromJson(data.cast<String, dynamic>());
  }

  Future<void> post({
    required String provider,
    required String contentUrl,
    required String episodeKey,
    required int atSec,
    required String kind,
    required String value,
  }) async {
    await dio.post(
      '/reactions',
      data: {
        'provider': provider,
        'contentUrl': contentUrl,
        'episodeKey': episodeKey,
        'atSec': atSec,
        'kind': kind,
        'value': value,
      },
    );
  }
}
