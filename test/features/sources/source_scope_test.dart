// The sources list is filtered on one axis, and there are two.
//
// A row of chips could offer the ecosystem and nothing else. But for the
// extension ecosystems the ecosystem is not the end of the question: somebody
// with six CloudStream repositories installed has six separate sets of sources
// sitting in one alphabetical run of two hundred rows, and no way to ask which
// came from which. Every host reported the repository and it was written
// straight into `description` and read nowhere.
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/profile/data/models/provider_model.dart';
import 'package:soplay/features/sources/domain/source_ecosystem.dart';
import 'package:soplay/features/sources/domain/source_scope.dart';

ProviderEntity p(String id, {String repo = ''}) => ProviderEntity(
  id: id,
  name: id,
  image: '',
  url: '',
  description: '',
  domains: const [],
  repo: repo,
);

void main() {
  const hexated =
      'https://raw.githubusercontent.com/hexated/cloudstream-extensions-hexated/builds/plugins.json';
  const recloudstream =
      'https://raw.githubusercontent.com/recloudstream/extensions/builds/plugins.json';

  final library = [
    p('cs:one', repo: hexated),
    p('cs:two', repo: hexated),
    p('cs:three', repo: recloudstream),
    p(
      'an:four',
      repo:
          'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json',
    ),
    p('vidapi'),
  ];

  group('what a scope selects', () {
    test('all of it, by default', () {
      expect(library.where(SourceScope.all.matches).length, 5);
    });

    test('one ecosystem', () {
      const scope = SourceScope(ecosystem: SourceEcosystem.cloudstream);
      expect(library.where(scope.matches).map((s) => s.id), [
        'cs:one',
        'cs:two',
        'cs:three',
      ]);
    });

    test('one repository inside it', () {
      const scope = SourceScope(
        ecosystem: SourceEcosystem.cloudstream,
        repo: hexated,
      );
      expect(library.where(scope.matches).map((s) => s.id), [
        'cs:one',
        'cs:two',
      ]);
    });

    test("and Sozo's own sources are an ecosystem like any other", () {
      const scope = SourceScope(ecosystem: SourceEcosystem.sozo);
      expect(library.where(scope.matches).map((s) => s.id), ['vidapi']);
    });
  });

  group('counting', () {
    final counts = SourceScopeCounts.of(library);

    test('by ecosystem', () {
      expect(counts.total, 5);
      expect(counts.byEcosystem[SourceEcosystem.cloudstream], 3);
      expect(counts.byEcosystem[SourceEcosystem.aniyomi], 1);
      expect(counts.byEcosystem[SourceEcosystem.sozo], 1);
    });

    test('and by repository within one', () {
      expect(
        counts.countFor(
          const SourceScope(
            ecosystem: SourceEcosystem.cloudstream,
            repo: hexated,
          ),
        ),
        2,
      );
      expect(
        counts.countFor(
          const SourceScope(
            ecosystem: SourceEcosystem.cloudstream,
            repo: recloudstream,
          ),
        ),
        1,
      );
    });

    test('repos are offered only where there is a choice', () {
      // One entry is a label pretending to be a control, and it says nothing
      // the ecosystem row above it has not already said.
      expect(counts.reposIn(SourceEcosystem.cloudstream), hasLength(2));
      expect(counts.reposIn(SourceEcosystem.aniyomi), isEmpty);
      expect(counts.reposIn(SourceEcosystem.sozo), isEmpty);
    });

    test('and the busiest repo comes first', () {
      expect(counts.reposIn(SourceEcosystem.cloudstream).first.key, hexated);
    });

    test('a source with no repository is still counted in its ecosystem', () {
      // Sozo's own providers and the catalogues have no repo to belong to.
      final c = SourceScopeCounts.of([p('vidapi'), p('cs:x')]);
      expect(c.byEcosystem[SourceEcosystem.sozo], 1);
      expect(c.byRepo[SourceEcosystem.cloudstream], isNull);
    });
  });

  group('what a repository is called on a button', () {
    test('a GitHub raw url becomes the account', () {
      // Ninety characters of raw.githubusercontent.com tells nobody anything;
      // the owner is how these are actually talked about.
      expect(repoLabel(hexated), 'hexated/cloudstream-hexated');
      expect(
        repoLabel(
          'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json',
        ),
        'keiyoushi',
      );
    });

    test('the repo name is dropped when it only repeats the owner', () {
      expect(
        repoLabel(
          'https://raw.githubusercontent.com/recloudstream/extensions/builds/plugins.json',
        ),
        'recloudstream',
      );
    });

    test('anything else becomes its host', () {
      expect(
        repoLabel('https://sources.example.com/a/b/index.json'),
        'sources.example.com',
      );
      expect(repoLabel('https://www.example.com/i.json'), 'example.com');
    });

    test('and a url nobody can read is still better than "unknown"', () {
      expect(repoLabel('not a url'), 'not a url');
      expect(repoLabel(''), '');
      expect(repoLabel('   '), '');
    });
  });

  group('the repository reaches the entity at all', () {
    test('a host that reports one', () {
      // Every extension host already sent this and ProviderModel dropped it,
      // which is why the filter could not exist.
      final model = ProviderModel.fromJson({
        'id': 'cs:x',
        'name': 'X',
        'repo': hexated,
      });
      expect(model.repo, hexated);
    });

    test('and one that does not', () {
      expect(ProviderModel.fromJson({'id': 'vidapi'}).repo, '');
    });

    test('it survives being cached and read back', () {
      final model = ProviderModel.fromJson({'id': 'cs:x', 'repo': hexated});
      expect(ProviderModel.fromJson(model.toJson()).repo, hexated);
    });
  });
}
