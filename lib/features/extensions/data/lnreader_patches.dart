import 'package:soplay/features/extensions/domain/entities/mangayomi_source.dart';

/// A fixed build of an official LNReader plugin, shipped in the app.
///
/// Built from upstream's TypeScript with the change in
/// `tool/lnreader_patches/`. It stands in only for the exact [version] it
/// was made against: once upstream publishes a newer one, that one runs.
class LnReaderPatch {
  const LnReaderPatch(this.id, this.version);

  /// The plugin's own id, without the app's `ln.` prefix.
  final String id;

  final String version;

  String get asset => 'assets/lnreader/patches/$id.js';
}

class LnReaderPatches {
  const LnReaderPatches._();

  static const List<LnReaderPatch> all = [
    // Chapters come from the rendered reader; the API stopped serving them.
    LnReaderPatch('genesistudio', '2.0.1'),
    // The rankings moved into the page's Next.js data.
    LnReaderPatch('kakuyomu', '1.0.0'),
  ];

  /// Forks reuse the official ids, so the code url has to be upstream's too.
  static LnReaderPatch? forSource(MangayomiSource source) {
    if (!source.isLnReader ||
        !source.sourceCodeUrl.toLowerCase().contains(
          '/lnreader/lnreader-plugins/',
        )) {
      return null;
    }
    for (final patch in all) {
      if (source.id == 'ln.${patch.id}' && source.version == patch.version) {
        return patch;
      }
    }
    return null;
  }
}
