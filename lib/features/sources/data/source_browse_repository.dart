import 'package:dio/dio.dart';
import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/manga/manga_channel.dart';
import 'package:soplay/features/extensions/data/mangayomi_bridge.dart';
import 'package:soplay/features/jellyfin/data/jellyfin_bridge.dart';
import 'package:soplay/features/home/data/models/home_data_model.dart';
import 'package:soplay/features/home/domain/entities/home_data_entity.dart';

/// One source's catalogue, without making it the app's source.
///
/// Browsing used to mean switching. The provider rode on every `/contents/`
/// request as ambient state read from Hive, so looking at what another source
/// carries meant becoming that source and being put back on Home — which is
/// why changing source felt like a settings trip rather than a look around.
///
/// The seam to avoid that was already in place and had no caller:
/// `ProviderInterceptor` leaves an explicit `provider` query parameter alone,
/// and `DetailArgs` carries one, so a card opened from here reaches the right
/// source without anything global moving.
///
/// Four of the five kinds of source never touch the backend at all: CloudStream,
/// Aniyomi, Manga and Mangayomi all answer from the device. Routing by prefix
/// mirrors `HomeRepositoryImpl.loadHome`, which is the only other place that has
/// to know this — sending a `cs:` id to `/contents/home` is what made opening
/// XD Movies here answer 400.
class SourceBrowseRepository {
  const SourceBrowseRepository({
    required this.dio,
    required this.bridge,
    this.jellyfin,
  });

  final Dio dio;
  final MangayomiBridge bridge;
  final JellyfinBridge? jellyfin;

  Future<HomeDataEntity> load(String providerId) async {
    final bare = providerId.length > 3 ? providerId.substring(3) : providerId;

    if (providerId.startsWith('cs:')) {
      return _fromHost(() => CloudStreamChannel.getMainPage(bare), 'CloudStream');
    }
    if (providerId.startsWith('an:')) {
      return _fromHost(() => AniyomiChannel.getMainPage(bare), 'Aniyomi');
    }
    if (providerId.startsWith('mn:')) {
      return _fromHost(() => MangaChannel.getMainPage(bare), 'Manga');
    }
    if (providerId.startsWith('my:')) {
      return _fromHost(() => bridge.getMainPage(bare), 'Mangayomi');
    }
    final jf = jellyfin;
    if (jf != null && providerId.startsWith('jf:')) {
      return _fromHost(() => jf.getMainPage(bare), 'Jellyfin');
    }

    final res = await dio.get<Map<String, dynamic>>(
      '/contents/home',
      queryParameters: {'provider': providerId},
    );
    return HomeDataModel.fromJson(res.data ?? const <String, dynamic>{});
  }

  /// An on-device host's catalogue.
  ///
  /// Each reports *why* it came back empty in an `error` field — a bad apk, a
  /// dex link failure, the HTTP status the source answered with — and that is
  /// worth more than "nothing here", because it is the difference between a
  /// user who can re-add the repo and one staring at a blank screen.
  Future<HomeDataEntity> _fromHost(
    Future<Map<String, dynamic>> Function() call,
    String label,
  ) async {
    final map = await call();
    final error = map['error'];
    final sections = map['sections'];
    if (sections is! List || sections.isEmpty) {
      throw SourceBrowseException(
        error is String && error.isNotEmpty ? '$label: $error' : null,
      );
    }
    return HomeDataModel.fromJson(map);
  }
}

/// A browse failure with something a person can read.
///
/// The raw object went to the screen before this existed, so a source the
/// backend does not know answered with eleven lines of DioException about
/// `validateStatus` and a link to the MDN page for HTTP 400.
class SourceBrowseException implements Exception {
  const SourceBrowseException(this.message);

  /// Null when there is nothing specific to say; the UI supplies the wording.
  final String? message;

  @override
  String toString() => message ?? '';
}
