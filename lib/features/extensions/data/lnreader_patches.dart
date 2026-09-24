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
    LnReaderPatch('69shu', '0.2.2'),
    LnReaderPatch('blogdoamonnovels', '1.0.1'),
    LnReaderPatch('cherrymistcafe', '1.2.1'),
    LnReaderPatch('chrysanthemumgarden', '1.0.3'),
    LnReaderPatch('crimsonscrolls', '1.0.1'),
    LnReaderPatch('DDL.com', '1.1.1'),
    LnReaderPatch('dragonholic', '2.2.0'),
    LnReaderPatch('ekitaplar', '2.2.0'),
    LnReaderPatch('galaxynovels', '1.1.0'),
    LnReaderPatch('genesistudio', '2.0.1'),
    LnReaderPatch('hizomanga', '2.2.0'),
    LnReaderPatch('indratranslations', '1.2.1'),
    LnReaderPatch('ixdzs8', '2.2.9'),
    LnReaderPatch('jgarden', '1.0.5'),
    LnReaderPatch('kakuyomu', '1.0.0'),
    LnReaderPatch('kdtnovels', '1.1.10'),
    LnReaderPatch('kolnovel', '1.1.20'),
    LnReaderPatch('mtl-novel', '2.2.0'),
    LnReaderPatch('namevt', '1.1.10'),
    LnReaderPatch('penguinsquad', '1.2.0'),
    LnReaderPatch('ragnarscans', '2.2.0'),
    LnReaderPatch('ranobes', '2.0.2'),
    LnReaderPatch('reinowuxia', '1.0.0'),
    LnReaderPatch('riwyat', '2.2.0'),
    LnReaderPatch('TCSega', '1.1.10'),
    LnReaderPatch('webnoveloku', '2.2.0'),
    LnReaderPatch('wordexcerpt', '2.2.0'),
    LnReaderPatch('zelluloza', '1.0.3'),
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
