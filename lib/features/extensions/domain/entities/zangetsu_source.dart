/// One source of an external Zangetsu repo, as `/extension-repos/zangetsu`
/// lists it, plus what the device keeps once it is installed.
class ZangetsuSource {
  const ZangetsuSource({
    required this.id,
    required this.providerId,
    required this.name,
    required this.repoUrl,
    required this.file,
    this.lang = 'en',
    this.type = 'movie',
    this.version = '0',
    this.icon,
    this.nsfw = false,
    this.builtIn = false,
    this.enabled = true,
  });

  final String id;

  /// `zx-<id>`: namespaced so it can never take over a built-in provider.
  final String providerId;
  final String name;
  final String repoUrl;
  final String file;
  final String lang;
  final String type;
  final String version;
  final String? icon;
  final bool nsfw;

  /// Sozo already ships this source; its own provider is the one used.
  final bool builtIn;
  final bool enabled;

  bool get isAnime => type == 'anime';

  bool get isLive => type == 'live' || type == 'tv';

  static ZangetsuSource? fromJson(Map<String, dynamic> json, {String? repoUrl}) {
    final id = (json['id'] as String?)?.trim() ?? '';
    final file = (json['file'] as String?)?.trim() ?? '';
    final repo = repoUrl ?? (json['repoUrl'] as String?)?.trim() ?? '';
    if (id.isEmpty || file.isEmpty || repo.isEmpty) return null;
    final providerId = (json['providerId'] as String?)?.trim();
    final icon = (json['icon'] as String?)?.trim();
    return ZangetsuSource(
      id: id,
      providerId: providerId == null || providerId.isEmpty
          ? 'zx-$id'
          : providerId,
      name: ((json['name'] as String?)?.trim().isNotEmpty ?? false)
          ? (json['name'] as String).trim()
          : id,
      repoUrl: repo,
      file: file,
      lang: ((json['lang'] as String?)?.trim().isNotEmpty ?? false)
          ? (json['lang'] as String).trim().toLowerCase()
          : 'en',
      type: ((json['type'] as String?)?.trim().isNotEmpty ?? false)
          ? (json['type'] as String).trim().toLowerCase()
          : 'movie',
      version: json['version']?.toString().trim() ?? '0',
      icon: icon == null || icon.isEmpty ? null : icon,
      nsfw: json['nsfw'] == true,
      builtIn: json['builtIn'] == true,
      enabled: json['enabled'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'providerId': providerId,
    'name': name,
    'repoUrl': repoUrl,
    'file': file,
    'lang': lang,
    'type': type,
    'version': version,
    if (icon != null) 'icon': icon,
    'nsfw': nsfw,
    'builtIn': builtIn,
    'enabled': enabled,
  };

  ZangetsuSource copyWith({bool? enabled, bool? builtIn}) => ZangetsuSource(
    id: id,
    providerId: providerId,
    name: name,
    repoUrl: repoUrl,
    file: file,
    lang: lang,
    type: type,
    version: version,
    icon: icon,
    nsfw: nsfw,
    builtIn: builtIn ?? this.builtIn,
    enabled: enabled ?? this.enabled,
  );
}
