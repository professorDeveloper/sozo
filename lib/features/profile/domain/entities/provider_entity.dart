class ExtractorRef {
  final String name;
  final int version;
  final String scope;
  final String url;

  const ExtractorRef({
    required this.name,
    required this.version,
    required this.scope,
    required this.url,
  });
}

class ProviderEntity {
  final String id;
  final String name;
  final String image;
  final String url;
  final String description;
  final List<String> domains;
  final String mode;
  final String category;
  final bool requiresCfBypass;

  /// The source can be browsed but nothing on it will play.
  ///
  /// Set by the backend when a provider's media has gone away at the source
  /// while its catalog still answers — mochitv, whose storage stopped serving,
  /// is the current case. Surfacing it means a user learns the source is
  /// read-only from the list, instead of by tapping an episode and watching a
  /// player fail.
  final bool browseOnly;

  /// Why [browseOnly] is set, in the user's language. Backend-supplied.
  final String? browseOnlyReason;

  final bool nsfw;
  final ExtractorRef? extractor;

  const ProviderEntity({
    required this.id,
    required this.name,
    required this.image,
    required this.url,
    required this.description,
    required this.domains,
    this.mode = 'server',
    this.category = 'other',
    this.requiresCfBypass = false,
    this.browseOnly = false,
    this.browseOnlyReason,
    this.nsfw = false,
    this.extractor,
  });

  /// Whether this provider can serve content with the backend unreachable.
  ///
  /// Only the on-device plugin hosts qualify: CloudStream (`cs:`), Aniyomi
  /// (`an:`) and Manga (`mn:`) resolve entirely through their platform
  /// channels. Everything else needs the API — server providers obviously, but
  /// also JS `hybrid`/`client` providers, because [ExtractorRunner] fetches
  /// `/extractors/runtime` from our backend before it can run any extractor.
  bool get isServerIndependent =>
      id.startsWith('cs:') || id.startsWith('an:') || id.startsWith('mn:');

  bool get scopesResolveMedia =>
      extractor != null &&
      (extractor!.scope == 'all' || extractor!.scope == 'resolveMedia');

  bool get scopesAll => extractor != null && extractor!.scope == 'all';
}
