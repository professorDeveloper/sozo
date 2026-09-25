import 'package:soplay/core/error/result.dart';
import '../entities/playback_entity.dart';
import '../repositories/detail_repository.dart';

class GetEpisodesUseCase {
  final DetailRepository repository;
  const GetEpisodesUseCase(this.repository);

  Future<Result<PlaybackEntity>> call(
    String contentUrl, {
    int page = 1,
    int size = 100,
    String sort = 'asc',
    String? provider,
  }) => repository.getEpisodes(
    contentUrl,
    page: page,
    size: size,
    sort: sort,
    provider: provider,
  );
}
