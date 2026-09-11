import 'package:dio/dio.dart';
import 'package:soplay/features/extensions/data/mangayomi_bridge.dart';
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
/// Mangayomi sources answer from the device rather than the backend, and
/// `getMainPage` already returns the same `{provider, banner, sections}` shape
/// the backend does — so both kinds parse through one model and render through
/// one widget instead of two catalogue screens that drift.
class SourceBrowseRepository {
  const SourceBrowseRepository({required this.dio, required this.bridge});

  final Dio dio;
  final MangayomiBridge bridge;

  Future<HomeDataEntity> load(String providerId) async {
    if (providerId.startsWith('my:')) {
      final data = await bridge.getMainPage(MangayomiBridge.bare(providerId));
      final sections = data['sections'];
      final error = data['error'];
      // The bridge reports a dead source in the payload rather than by
      // throwing, because a source that implements only one of popular/latest
      // is a real configuration and not a failure. Empty AND carrying an error
      // is the case that is actually broken.
      if ((sections is! List || sections.isEmpty) && error != null) {
        throw SourceBrowseException(error.toString());
      }
      return HomeDataModel.fromJson(data);
    }

    final res = await dio.get<Map<String, dynamic>>(
      '/contents/home',
      queryParameters: {'provider': providerId},
    );
    return HomeDataModel.fromJson(res.data ?? const <String, dynamic>{});
  }
}

class SourceBrowseException implements Exception {
  const SourceBrowseException(this.message);

  final String message;

  @override
  String toString() => message;
}
