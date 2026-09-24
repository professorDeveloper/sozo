// A whole ecosystem, reached through the runtime that was already there.
//
// Sozo could read light novels and had almost nowhere to read them from: a
// novel source is a Mangayomi source whose index declares `itemType: novel`,
// and most installs have none — which is why CatalogueResolver widens the
// light-novel shelf to the comic readers and caveats every answer. LNReader's
// index is 279 of them.
//
// The plugins are CommonJS bundles rather than Mangayomi classes, so the
// difference between the two ecosystems is entirely in which loader compiles
// the code. Everything after that — search, home, detail, chapters, the reader,
// downloads, EPUB export, read state — is the same object shape and needed no
// changes at all. These tests pin that boundary.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/extensions/data/extension_repo_defaults.dart';
import 'package:soplay/features/extensions/domain/entities/extension_repo_entity.dart';
import 'package:soplay/features/extensions/domain/entities/mangayomi_source.dart';

void main() {
  group('reading an LNReader index', () {
    const entry = {
      'id': 'allnovel',
      'name': 'AllNovel',
      'site': 'https://allnovel.test/',
      'lang': 'English',
      'version': '2.2.2',
      'url': 'https://plugins.test/AllNovel.js',
      'iconUrl': 'https://plugins.test/icon.png',
    };

    test('an entry becomes a novel source', () {
      final src = MangayomiSource.fromLnReaderJson(
        Map<String, dynamic>.from(entry),
        repoUrl: 'https://plugins.test/index.json',
      )!;
      expect(src.name, 'AllNovel');
      expect(src.baseUrl, 'https://allnovel.test/');
      expect(src.sourceCodeUrl, 'https://plugins.test/AllNovel.js');
      expect(src.itemType, MangayomiItemType.novel);
      expect(src.isJavaScript, isTrue);
    });

    test('and is marked so the right loader compiles it', () {
      final src = MangayomiSource.fromLnReaderJson(
        Map<String, dynamic>.from(entry),
        repoUrl: 'r',
      )!;
      expect(src.isLnReader, isTrue);
      expect(src.typeSource, MangayomiSource.lnReaderType);
    });

    test('the id is prefixed so two ecosystems cannot collide', () {
      // They share one registry in the runtime. A collision would silently
      // serve one source's chapters under another source's name.
      final src = MangayomiSource.fromLnReaderJson(
        Map<String, dynamic>.from(entry),
        repoUrl: 'r',
      )!;
      expect(src.id, 'ln.allnovel');
      expect(src.providerId, 'my:ln.allnovel');
    });

    test('an entry with nothing to run is dropped', () {
      expect(
        MangayomiSource.fromLnReaderJson(const {'id': 'x'}, repoUrl: 'r'),
        isNull,
      );
      expect(
        MangayomiSource.fromLnReaderJson(const {
          'id': 'x',
          'name': 'X',
        }, repoUrl: 'r'),
        isNull,
        reason: 'no code url',
      );
    });

    test('a stored source keeps its ecosystem across a restart', () {
      final src = MangayomiSource.fromLnReaderJson(
        Map<String, dynamic>.from(entry),
        repoUrl: 'r',
      )!;
      expect(MangayomiSource.fromJson(src.toJson()).isLnReader, isTrue);
    });
  });

  group('telling the two index shapes apart', () {
    test('by what the entries carry, not by where they came from', () {
      // A mirror, a fork or a local copy of either index has to keep working,
      // so nothing here looks at the hostname.
      expect(
        MangayomiSource.looksLikeLnReaderIndex([
          {'id': 'a', 'url': 'https://p/a.js', 'site': 'https://a.test/'},
        ]),
        isTrue,
      );
      expect(
        MangayomiSource.looksLikeLnReaderIndex([
          {'id': 'a', 'sourceCodeUrl': 'https://p/a.js', 'baseUrl': 'x'},
        ]),
        isFalse,
      );
    });

    test('and anything else is not one', () {
      expect(MangayomiSource.looksLikeLnReaderIndex(const []), isFalse);
      expect(MangayomiSource.looksLikeLnReaderIndex(null), isFalse);
      expect(MangayomiSource.looksLikeLnReaderIndex(const {'a': 1}), isFalse);
      expect(MangayomiSource.looksLikeLnReaderIndex(const ['x']), isFalse);
    });
  });

  group('where it is plugged in', () {
    test('the shim ships as an asset', () {
      expect(File('assets/js/lnreader.js').existsSync(), isTrue);
    });

    test('and is evaluated after the bridge, not before', () {
      // It uses the `fetch` the bridge installs, which is what carries Sozo's
      // user agent, cookie jar and Cloudflare clearance. Reaching the raw one
      // would be blocked where the rest of the app is not.
      final runtime = File(
        'lib/features/extensions/data/mangayomi_runtime.dart',
      ).readAsStringSync();
      final bridgeAt = runtime.indexOf('mangayomi_bridge.js');
      final shimAt = runtime.indexOf('lnreader.js');
      expect(bridgeAt, greaterThan(-1));
      expect(shimAt, greaterThan(bridgeAt));
    });

    test('the loader branches on the source, not on the code', () {
      final runtime = File(
        'lib/features/extensions/data/mangayomi_runtime.dart',
      ).readAsStringSync();
      expect(runtime, contains('source.isLnReader'));
      expect(runtime, contains('__sozoLoadLnReader'));
    });

    test('and the repo is offered without anyone typing a url', () {
      final repo = ExtensionRepoDefaults.forKind(
        ExtensionRepoKind.mangayomi,
      ).firstWhere((r) => r.name == 'LNReader');
      expect(repo.url, contains('lnreader-plugins'));
      expect(repo.novelUrl, isNotNull);
    });

    test('community plugin repos are offered as novel indexes too', () {
      final repos = ExtensionRepoDefaults.forKind(ExtensionRepoKind.mangayomi);
      for (final name in ['SpaceBattles & SV', 'Tausif-Husine']) {
        final repo = repos.firstWhere((r) => r.name == name);
        expect(repo.url, endsWith('/.dist/plugins.min.json'));
        expect(repo.novelUrl, repo.url);
      }
      final orders = repos.map((r) => r.order).toList();
      expect(orders.toSet().length, orders.length);
    });
  });
}
