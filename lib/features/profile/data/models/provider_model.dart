import '../../domain/entities/provider_entity.dart';

class ProviderModel extends ProviderEntity {
  const ProviderModel({
    required super.id,
    required super.name,
    required super.image,
    required super.url,
    required super.description,
    required super.domains,
    super.mode,
    super.category,
    super.requiresCfBypass,
    super.browseOnly,
    super.browseOnlyReason,
    super.nsfw,
    super.lang,
    super.extractor,
  });

  factory ProviderModel.fromJson(Map<String, dynamic> json) {
    final id =
        json['id'] as String? ??
        json['_id'] as String? ??
        json['slug'] as String? ??
        '';
    final name = json['name'] as String? ?? id;

    return ProviderModel(
      id: id,
      name: name,
      image: json['image'] as String? ?? '',
      url: json['url'] as String? ?? '',
      description: json['description'] as String? ?? '',
      domains: (json['domains'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
      mode: json['mode'] as String? ?? 'server',
      category: (json['category'] as String?)?.trim().isNotEmpty == true
          ? json['category'] as String
          : 'other',
      requiresCfBypass: json['requiresCfBypass'] == true,
      browseOnly: json['browseOnly'] == true,
      browseOnlyReason: (json['browseOnlyReason'] as String?)?.trim(),
      nsfw: json['nsfw'] == true,
      // Every host already sends this — AniyomiHost.providersJson,
      // MangaHost.providersJson and MangayomiBridge.listProviders all put a
      // `lang` in — and until now it was parsed by nobody, so the picker had no
      // idea any source had a language at all.
      lang: (json['lang'] as String?)?.trim() ?? '',
      extractor: _parseExtractor(json['extractor']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'image': image,
    'url': url,
    'description': description,
    'domains': domains,
    'mode': mode,
    'category': category,
    'requiresCfBypass': requiresCfBypass,
    'browseOnly': browseOnly,
    if (browseOnlyReason != null) 'browseOnlyReason': browseOnlyReason,
    'nsfw': nsfw,
    if (lang.isNotEmpty) 'lang': lang,
    if (extractor != null)
      'extractor': {
        'name': extractor!.name,
        'version': extractor!.version,
        'scope': extractor!.scope,
        'url': extractor!.url,
      },
  };

  static ExtractorRef? _parseExtractor(dynamic raw) {
    if (raw is! Map) return null;
    final name = raw['name'] as String?;
    final url = raw['url'] as String?;
    if (name == null || name.isEmpty || url == null || url.isEmpty) return null;
    final version = (raw['version'] as num?)?.toInt() ?? 0;
    final scope = raw['scope'] as String? ?? 'resolveMedia';
    return ExtractorRef(name: name, version: version, scope: scope, url: url);
  }
}
