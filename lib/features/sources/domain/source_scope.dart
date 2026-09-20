import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/sources/domain/source_ecosystem.dart';

/// Which slice of the installed sources is being looked at.
///
/// The browse list is several hundred rows across five ecosystems, and for the
/// extension ones the ecosystem is not the end of it: somebody with six
/// CloudStream repositories installed has six separate sets of sources sitting
/// in one alphabetical run, with no way to ask which came from which. The repo
/// was reported by every host and thrown away — see [ProviderEntity.repo].
///
/// One value, two levels: an ecosystem, and optionally a repository inside it.
/// A repo without an ecosystem is not a state the UI can produce, because a
/// repo only appears in the menu once its ecosystem is chosen.
class SourceScope {
  const SourceScope({this.ecosystem, this.repo});

  /// Everything.
  static const SourceScope all = SourceScope();

  final SourceEcosystem? ecosystem;

  /// A repository url, or null for every repo in [ecosystem].
  final String? repo;

  bool get isAll => ecosystem == null && repo == null;

  bool matches(ProviderEntity p) {
    final e = ecosystem;
    if (e != null && SourceEcosystem.of(p.id) != e) return false;
    final r = repo;
    if (r != null && p.repo != r) return false;
    return true;
  }

  SourceScope withEcosystem(SourceEcosystem? e) => SourceScope(ecosystem: e);

  SourceScope withRepo(String? r) => SourceScope(ecosystem: ecosystem, repo: r);

  @override
  bool operator ==(Object other) =>
      other is SourceScope &&
      other.ecosystem == ecosystem &&
      other.repo == repo;

  @override
  int get hashCode => Object.hash(ecosystem, repo);

  @override
  String toString() => 'SourceScope($ecosystem, $repo)';
}

/// How many sources sit in each ecosystem, and in each repo within one.
class SourceScopeCounts {
  const SourceScopeCounts({required this.byEcosystem, required this.byRepo});

  factory SourceScopeCounts.of(Iterable<ProviderEntity> providers) {
    final byEcosystem = <SourceEcosystem, int>{};
    final byRepo = <SourceEcosystem, Map<String, int>>{};
    for (final p in providers) {
      final e = SourceEcosystem.of(p.id);
      byEcosystem[e] = (byEcosystem[e] ?? 0) + 1;
      if (p.repo.isEmpty) continue;
      (byRepo[e] ??= <String, int>{}).update(
        p.repo,
        (n) => n + 1,
        ifAbsent: () => 1,
      );
    }
    return SourceScopeCounts(byEcosystem: byEcosystem, byRepo: byRepo);
  }

  final Map<SourceEcosystem, int> byEcosystem;
  final Map<SourceEcosystem, Map<String, int>> byRepo;

  int get total => byEcosystem.values.fold(0, (a, b) => a + b);

  int countFor(SourceScope scope) {
    final e = scope.ecosystem;
    if (e == null) return total;
    final r = scope.repo;
    if (r == null) return byEcosystem[e] ?? 0;
    return byRepo[e]?[r] ?? 0;
  }

  /// The repositories inside [e], most sources first.
  ///
  /// Only worth offering when there is more than one: a single entry is a
  /// label pretending to be a control, and it would say nothing the ecosystem
  /// row above it has not already said.
  List<MapEntry<String, int>> reposIn(SourceEcosystem e) {
    final repos = byRepo[e];
    if (repos == null || repos.length < 2) return const [];
    return repos.entries.toList()..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
  }
}

/// A repository url as something worth putting on a button.
///
/// A raw index url is ninety characters of raw.githubusercontent.com and tells
/// nobody anything; the owner's name is the part people actually recognise,
/// because that is how these repositories are talked about. So a GitHub url
/// becomes the account it belongs to, and anything else becomes its host.
///
/// Falls back to the url itself rather than to a placeholder: a url nobody can
/// read is still a url somebody can recognise, and "Unknown" is not.
String repoLabel(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return '';
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.host.isEmpty) return trimmed;
  final host = uri.host.toLowerCase();
  final segments = uri.pathSegments;
  if ((host == 'raw.githubusercontent.com' ||
          host == 'github.com' ||
          host == 'gitlab.com' ||
          host == 'raw.gitmirror.com') &&
      segments.isNotEmpty) {
    final owner = segments.first;
    // `owner/repo` when the repo name says something the owner does not, which
    // is the case for anybody publishing more than one.
    if (segments.length > 1) {
      // "cloudstream-extensions-hexated" is not a name, it is a name with
      // boilerplate in it. Dropped as whole words wherever they sit, because
      // these repositories put them at either end and in the middle.
      final repo = segments[1]
          .split(RegExp(r'[-_]'))
          .where(
            (w) => !RegExp(
              r'^(extensions?|repo|repository|plugins?|sources?)$',
              caseSensitive: false,
            ).hasMatch(w),
          )
          .join('-')
          .trim();
      if (repo.isNotEmpty && repo.toLowerCase() != owner.toLowerCase()) {
        return '$owner/$repo';
      }
    }
    return owner;
  }
  return host.startsWith('www.') ? host.substring(4) : host;
}
