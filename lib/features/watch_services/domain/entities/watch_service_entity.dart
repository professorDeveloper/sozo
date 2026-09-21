/// What a service carries.
enum WatchServiceMedia {
  movie('movie'),
  tv('tv');

  const WatchServiceMedia(this.id);

  final String id;

  static WatchServiceMedia? fromId(String? id) {
    for (final m in values) {
      if (m.id == id) return m;
    }
    return null;
  }
}

/// One streaming service, in one country.
///
/// Called a SERVICE and never a provider. `provider` already means source
/// everywhere in this app — the `cs:` / `an:` / `mn:` / `my:` / `cat:` ids, the
/// list the picker shows, `ProviderEntity` itself — and TMDB calls these things
/// "watch providers". Using their word here would make two unrelated ideas
/// share a name in the one place both of them appear.
class WatchServiceEntity {
  const WatchServiceEntity({
    required this.id,
    required this.name,
    this.slug = '',
    this.logo,
    this.priority = 9999,
    this.types = const [],
  });

  /// TMDB's numeric id. This is what a browse request takes; the slug is for
  /// links and analytics.
  final int id;

  final String name;
  final String slug;

  /// The service's mark. Null happens — TMDB occasionally lists a service with
  /// no logo on file — and whatever draws it falls back to initials rather than
  /// to a generic icon, because a row of identical glyphs says nothing.
  final String? logo;

  /// TMDB's own ordering for this country, lower first.
  ///
  /// The only editorial signal available, and the reason the rail leads with
  /// the services people in that country actually have. Alphabetical across a
  /// row of twelve marks is the same as random.
  final int priority;

  /// Whether it has films, series, or both.
  ///
  /// Decides whether the browse screen offers a Movies/Series toggle at all — a
  /// control with one option is a label, and one that switches to an empty list
  /// is worse.
  final List<WatchServiceMedia> types;

  bool get hasMovies => types.contains(WatchServiceMedia.movie);
  bool get hasSeries => types.contains(WatchServiceMedia.tv);

  /// Up to two letters, for a service with no mark on file.
  String get initials {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final w = words.first;
      return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
    }
    return (words.first[0] + words.elementAt(1)[0]).toUpperCase();
  }
}
