import 'package:easy_localization/easy_localization.dart';

/// Which runtime a source comes from.
///
/// The browse list mixes four ecosystems and Sozo's own cloud sources in one
/// alphabetical run of several hundred rows, and the only thing separating them
/// was a word in grey under each name. Somebody looking for "the one I added
/// from CloudStream" had to read every row. This is the axis people actually
/// filter on — far more than the first letter of a name they do not remember.
enum SourceEcosystem {
  /// Sozo's own, served by the backend. Nothing to install.
  sozo('sozo', 'sources.eco_sozo'),
  cloudstream('cs:', 'sources.eco_cloudstream'),
  aniyomi('an:', 'sources.eco_aniyomi'),
  manga('mn:', 'sources.eco_manga'),
  mangayomi('my:', 'sources.eco_mangayomi');

  const SourceEcosystem(this.prefix, this.labelKey);

  /// The provider-id prefix that identifies it. [sozo] has none — a cloud
  /// source is anything with no extension prefix at all.
  final String prefix;

  final String labelKey;

  String get label => labelKey.tr();

  /// The ecosystem [providerId] belongs to.
  static SourceEcosystem of(String providerId) {
    for (final e in values) {
      if (e != sozo && providerId.startsWith(e.prefix)) return e;
    }
    return sozo;
  }
}
