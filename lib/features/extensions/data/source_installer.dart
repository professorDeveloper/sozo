import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/manga/manga_channel.dart';
import 'package:soplay/features/extensions/data/extension_repo_defaults.dart';
import 'package:soplay/features/extensions/data/mangayomi_repo_store.dart';
import 'package:soplay/features/extensions/domain/entities/catalog_source_entity.dart';
import 'package:soplay/features/extensions/domain/entities/extension_repo_entity.dart';

/// Resolves old catalog responses too, without guessing paths for custom repos.
String sourceInstallUrl(CatalogSourceEntity source) {
  if (source.sourceIndexUrl.isNotEmpty) return source.sourceIndexUrl;
  if (source.kind == ExtensionRepoKind.mangayomi) {
    for (final repo in ExtensionRepoDefaults.forKind(source.kind)) {
      if (repo.url != source.repoUrl) continue;
      return switch (source.itemType) {
        CatalogItemType.novel => repo.novelUrl ?? source.repoUrl,
        CatalogItemType.anime => repo.animeUrl ?? source.repoUrl,
        _ => source.repoUrl,
      };
    }
  }
  return source.repoUrl;
}

Future<int> installCatalogSource(
  CatalogSourceEntity source,
  MangayomiRepoStore store,
) async {
  final url = sourceInstallUrl(source);
  Map<String, dynamic> result;
  String countKey;
  switch (source.kind) {
    case ExtensionRepoKind.cloudstream:
      var internalName = source.externalId;
      if (internalName.isEmpty) {
        final index = await CloudStreamChannel.listRepoPlugins(url);
        final matches = (index['plugins'] as List? ?? const [])
            .whereType<Map>()
            .where(
              (p) =>
                  p['name'] == source.name || p['internalName'] == source.name,
            )
            .toList();
        if (matches.length != 1) {
          throw StateError('Source not found in repository');
        }
        internalName = matches.single['internalName']?.toString() ?? '';
      }
      if (internalName.isEmpty) throw StateError('Missing plugin identity');
      result = await CloudStreamChannel.installPlugin(url, internalName);
      countKey = 'pluginCount';
      if (result['providers'] case final List providers
          when providers.isEmpty) {
        throw StateError('Plugin could not load any providers');
      }
    case ExtensionRepoKind.aniyomi:
      result = await AniyomiChannel.addRepo(url);
      countKey = 'sourceCount';
    case ExtensionRepoKind.manga:
      result = await MangaChannel.addRepo(url);
      countKey = 'sourceCount';
    case ExtensionRepoKind.mangayomi:
      result = await store.addRepo(url);
      countKey = 'total';
  }
  if (result['error'] case final String error when error.isNotEmpty) {
    throw StateError(error);
  }
  return (result[countKey] as num?)?.toInt() ?? 0;
}
