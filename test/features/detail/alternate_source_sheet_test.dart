import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/matching/title_match.dart';
import 'package:soplay/features/detail/data/source_choice_store.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';
import 'package:soplay/features/detail/domain/services/alternate_source_service.dart';
import 'package:soplay/features/detail/presentation/widgets/alternate_source_sheet.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/search/domain/entities/cross_search_result.dart';

/// The switcher, drawn against a service that answers instantly and exactly as
/// the test says.
///
/// No translations are loaded, so every `.tr()` renders as its own key. That is
/// deliberate: it makes these assertions about WHICH sentence the sheet chose
/// rather than about its current wording, which is edited far more often than
/// its meaning. That the keys exist at all, and read as English, is asserted
/// separately at the bottom of this file against `assets/translations/en.json`.
class _Service implements AlternateSourceService {
  _Service({
    this.sources = const [],
    this.outcome = const AlternateSearchOutcome(asked: 2),
    this.results = const {},
  });

  /// What the automatic fan-out "found", in the order it finds it.
  final List<AlternateSource> sources;

  /// How the run ended, reported once the last row is out — which is the order
  /// the real service reports in.
  final AlternateSearchOutcome outcome;

  /// What each source answers a by-hand search with, by provider id. A source
  /// that is absent here answers null, i.e. is not reachable at all.
  final Map<String, ProviderSearchResult> results;

  /// Every by-hand search that was run: provider id and the query it carried.
  final List<(String, String)> handSearches = [];

  @override
  Stream<AlternateSource> find({
    required String title,
    required String excludeProvider,
    String titleProvider = '',
    List<ProviderEntity>? candidates,
    void Function(AlternateSearchOutcome outcome)? onOutcome,
  }) async* {
    for (final source in sources) {
      yield source;
    }
    onOutcome?.call(outcome);
  }

  @override
  Future<ProviderSearchResult?> searchOne({
    required String providerId,
    required String query,
    List<ProviderEntity>? candidates,
    int page = 1,
  }) async {
    handSearches.add((providerId, query));
    return results[providerId];
  }

  @override
  Future<PlayerArgs?> buildArgs({
    required AlternateSource source,
    required int? episodeNumber,
    Duration resumeAt = Duration.zero,
  }) async => null;

  /// Anything else is a call these tests did not expect the sheet to make, and
  /// a thrown NoSuchMethodError names it.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const String _title = 'Return of the Blossoming Blade';

MovieEntity _movie(String title) => MovieEntity(
  externalId: title,
  title: title,
  description: '',
  slug: title,
  url: 'https://src/${title.hashCode}',
  provider: 'an:x',
  thumbnail: null,
  year: null,
  rating: null,
  qualities: null,
  category: 'anime',
);

ProviderEntity _provider(String id, String name) => ProviderEntity(
  id: id,
  name: name,
  image: '',
  url: '',
  description: '',
  domains: const [],
  category: 'anime',
);

/// A row as the real service would hand it over: the match is computed, never
/// asserted into existence, so a fixture cannot claim a confidence the matcher
/// would not give it.
AlternateSource _source(String providerId, String name, String found) {
  return AlternateSource(
    provider: ProviderRef(
      id: providerId,
      name: name,
      kind: ProviderRef.kindOf(providerId, scopesAll: false),
    ),
    item: _movie(found),
    match: TitleMatch.of(query: _title, candidate: found),
  );
}

ProviderSearchResult _answer(
  String providerId,
  String name,
  List<String> titles, {
  ProviderSearchStatus status = ProviderSearchStatus.ok,
}) => ProviderSearchResult(
  provider: ProviderRef(
    id: providerId,
    name: name,
    kind: ProviderRef.kindOf(providerId, scopesAll: false),
  ),
  items: titles.map(_movie).toList(),
  status: status,
);

void main() {
  late _Box box;

  setUp(() => box = _Box());
  tearDown(() async => getIt.reset());

  /// The sheet on screen, with the service it talks to already registered.
  Future<void> pump(
    WidgetTester tester,
    _Service service, {
    List<ProviderEntity> candidates = const [],
    SourceChoiceStore? choices,
  }) async {
    getIt.registerSingleton<AlternateSourceService>(service);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlternateSourceSheet.withDependencies(
            title: _title,
            provider: 'vidapi',
            category: 'anime',
            episodeNumber: null,
            candidates: candidates,
            choices: choices ?? SourceChoiceStore(box: box),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// One tile in the grid, found by the title the source answered with.
  ///
  /// The rows became poster tiles — a list of names could not answer the
  /// question the sheet is for, which is "is this the show I was watching",
  /// and four sources spelling the title identically are told apart by their
  /// artwork in a way they never were by their names.
  Finder rowFor(String title) =>
      find.ancestor(of: find.text(title), matching: find.byType(Column)).first;

  /// The "Wrong title?" control on a tile.
  ///
  /// It is an icon with a spoken label rather than a text button: a tile is
  /// 132px wide and the words are not. Found the way a screen reader finds it,
  /// which is also the only way it is labelled.
  Finder wrongTitle() => find.bySemanticsLabel('player.alt_wrong_title');

  group('how sure the row is', () {
    testWidgets('a weak match is marked a guess and a strong one is not', (
      tester,
    ) async {
      // The fixture is only worth anything if the matcher really does put these
      // two in different bands, so that is asserted before the pixels are.
      final weak = TitleMatch.of(query: _title, candidate: 'Return of the Blade');
      expect(weak.isUsable, isTrue, reason: 'a rejected row is never drawn');
      expect(weak.confidence, TitleConfidence.weak);
      expect(
        TitleMatch.of(query: _title, candidate: _title).confidence,
        TitleConfidence.exact,
      );

      await pump(
        tester,
        _Service(
          sources: [
            _source('an:one', 'AniOne', _title),
            _source('an:two', 'AniTwo', 'Return of the Blade'),
          ],
        ),
        candidates: [_provider('an:one', 'AniOne'), _provider('an:two', 'AniTwo')],
      );

      expect(
        find.descendant(
          of: rowFor('Return of the Blade'),
          matching: find.text('player.alt_guess'),
        ),
        findsOneWidget,
      );
      // The certain row keeps the plain look it had. A badge on every row is a
      // badge nobody reads, and this is what makes the marked one legible.
      expect(
        find.descendant(
          of: rowFor(_title),
          matching: find.text('player.alt_guess'),
        ),
        findsNothing,
      );
    });

    testWidgets('the guess says so out loud as well as on screen', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        _Service(sources: [_source('an:two', 'AniTwo', 'Return of the Blade')]),
        candidates: [_provider('an:two', 'AniTwo')],
      );
      // Not colour, and not the icon alone: a screen reader gets a sentence it
      // can act on, which is the whole reason the pill carries a spoken label.
      expect(
        tester.getSemantics(find.text('player.alt_guess')).label,
        contains('player.alt_guess_spoken'),
      );
      handle.dispose();
    });
  });

  group('wrong title?', () {
    testWidgets('picking by hand replaces the row the matcher guessed', (
      tester,
    ) async {
      final service = _Service(
        sources: [_source('an:two', 'AniTwo', 'Return of the Blade')],
        results: _handAnswers(),
      );
      await pump(
        tester,
        service,
        candidates: [_provider('an:two', 'AniTwo')],
      );

      await tester.tap(
        find.descendant(
          of: rowFor('Return of the Blade'),
          matching: wrongTitle(),
        ),
      );
      await tester.pumpAndSettle();

      // Pre-filled with the title we were looking for: the usual correction is
      // that the source spells it almost the same.
      expect(service.handSearches, [('an:two', _title)]);

      await tester.tap(find.text('Hwagae Hyeongsa: The Blossoming Blade'));
      await tester.pumpAndSettle();

      expect(rowFor('Hwagae Hyeongsa: The Blossoming Blade'), findsOneWidget);
      expect(
        find.descendant(
          of: rowFor('Hwagae Hyeongsa: The Blossoming Blade'),
          matching: find.text('player.alt_your_pick'),
        ),
        findsOneWidget,
      );
      // One line per source. Leaving the overruled guess underneath would be
      // the switcher arguing with the person who read both titles.
      expect(find.text('Return of the Blade'), findsNothing);
    });

    testWidgets('is a real target, and not the one that starts playback', (
      tester,
    ) async {
      await pump(
        tester,
        _Service(sources: [_source('an:two', 'AniTwo', 'Return of the Blade')]),
        candidates: [_provider('an:two', 'AniTwo')],
      );
      final button = wrongTitle();
      final size = tester.getSize(button);
      // A phone target, not a 12pt word: this is reached one-handed by someone
      // who has already had one thing go wrong.
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
      // Inside the row it belongs to, and beside the row's own tap rather than
      // instead of it — the primary action is still "play this one".
      expect(
        find.descendant(of: rowFor('Return of the Blade'), matching: button),
        findsOneWidget,
      );
    });

    testWidgets('the correction is on disk before the sheet is closed', (
      tester,
    ) async {
      final service = _Service(
        sources: [_source('an:two', 'AniTwo', 'Return of the Blade')],
        results: _handAnswers(),
      );
      await pump(tester, service, candidates: [_provider('an:two', 'AniTwo')]);
      await tester.tap(wrongTitle().first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hwagae Hyeongsa: The Blossoming Blade'));
      await tester.pumpAndSettle();

      // Read through a store built from scratch, which is what the next launch
      // has: the record has to survive this object, not just this frame.
      final stored = SourceChoiceStore(box: box).get(_title, 'an:two');
      expect(stored?.title, 'Hwagae Hyeongsa: The Blossoming Blade');
      expect(stored?.providerName, 'AniTwo');
      expect(stored?.url, isNotEmpty);
    });

    testWidgets('a correction from a previous run is read back on the first '
        'frame, with nothing found this time', (tester) async {
      await SourceChoiceStore(box: box).remember(
        SourceChoice(
          subject: _title,
          providerId: 'an:two',
          providerName: 'AniTwo',
          url: 'https://anitwo/hwagae',
          title: 'Hwagae Hyeongsa: The Blossoming Blade',
          at: 5,
        ),
      );

      // The automatic search finds nothing at all — which is the case a
      // correction exists for. The row has to come from storage or not at all.
      await pump(
        tester,
        _Service(),
        candidates: [_provider('an:two', 'AniTwo')],
        choices: SourceChoiceStore(box: box),
      );

      expect(rowFor('Hwagae Hyeongsa: The Blossoming Blade'), findsOneWidget);
      expect(find.text('player.alt_your_pick'), findsOneWidget);
      // And the source it was made on is no longer reported as having nothing.
      expect(find.text('player.alt_unmatched'), findsNothing);
    });

    testWidgets('a correction asked for under another spelling still counts', (
      tester,
    ) async {
      // Stored while the player was opened from a catalogue that punctuates it
      // differently. The person corrected this show, not this string.
      await SourceChoiceStore(box: box).remember(
        SourceChoice(
          subject: 'Return of the Blossoming Blade!',
          providerId: 'an:two',
          providerName: 'AniTwo',
          url: 'https://anitwo/hwagae',
          title: 'Hwagae Hyeongsa',
          at: 5,
        ),
      );
      await pump(
        tester,
        _Service(),
        candidates: [_provider('an:two', 'AniTwo')],
      );
      expect(rowFor('Hwagae Hyeongsa'), findsOneWidget);
    });
  });

  group('sources that found nothing', () {
    testWidgets('are listed quietly and can be searched by hand', (
      tester,
    ) async {
      final service = _Service(
        sources: [_source('an:one', 'AniOne', _title)],
        results: {
          'an:two': _answer('an:two', 'AniTwo', [
            'Hwagae Hyeongsa: The Blossoming Blade',
          ]),
        },
      );
      await pump(
        tester,
        service,
        candidates: [
          _provider('an:one', 'AniOne'),
          _provider('an:two', 'AniTwo'),
          // The source the viewer is already on is not an alternative to it.
          _provider('vidapi', 'VidAPI'),
        ],
      );

      // One source answered, so this is not the empty state — it is the quiet
      // section underneath it, counting exactly the one source that did not.
      expect(find.text('player.alt_unmatched'), findsOneWidget);
      expect(find.text('AniTwo'), findsNothing);

      await tester.tap(find.text('player.alt_unmatched'));
      await tester.pumpAndSettle();
      expect(find.text('AniTwo'), findsOneWidget);
      expect(find.text('player.alt_search_by_hand'), findsOneWidget);

      await tester.tap(find.text('AniTwo'));
      await tester.pumpAndSettle();
      expect(service.handSearches, [('an:two', _title)]);

      await tester.tap(find.text('Hwagae Hyeongsa: The Blossoming Blade'));
      await tester.pumpAndSettle();

      // It answers for this title now, so it belongs in the list above rather
      // than in the list of sources that had nothing to say.
      expect(rowFor('Hwagae Hyeongsa: The Blossoming Blade'), findsOneWidget);
      expect(find.text('player.alt_unmatched'), findsNothing);
    });

    testWidgets('a source still searching is not yet a source that found '
        'nothing', (tester) async {
      getIt.registerSingleton<AlternateSourceService>(_Slow());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlternateSourceSheet.withDependencies(
              title: _title,
              provider: 'vidapi',
              category: 'anime',
              episodeNumber: null,
              candidates: [_provider('an:two', 'AniTwo')],
              choices: SourceChoiceStore(box: box),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('player.alt_searching'), findsOneWidget);
      expect(find.text('player.alt_unmatched'), findsNothing);
    });
  });

  group('which kind of empty', () {
    /// Every empty state the sheet can reach, and the sentence it must reach
    /// for. They were one message once, and four of these five were things that
    /// message asserted without ever having established them.
    const cases = <String, (AlternateSearchOutcome, String)>{
      'nobody was asked': (
        AlternateSearchOutcome(),
        'player.alt_none_asked',
      ),
      'the source list itself failed': (
        AlternateSearchOutcome(unavailable: true),
        'player.alt_unavailable',
      ),
      'everything that was asked failed': (
        AlternateSearchOutcome(asked: 3, failed: 3),
        'player.alt_all_failed',
      ),
      'some answered, some fell over': (
        AlternateSearchOutcome(asked: 3, failed: 1),
        'player.alt_some_failed',
      ),
      'everything answered and none of it was this show': (
        AlternateSearchOutcome(asked: 3),
        'player.alt_no_match',
      ),
    };

    for (final entry in cases.entries) {
      testWidgets(entry.key, (tester) async {
        await pump(tester, _Service(outcome: entry.value.$1));
        expect(find.text(entry.value.$2), findsOneWidget);
        for (final other in cases.values) {
          if (other.$2 == entry.value.$2) continue;
          expect(
            find.text(other.$2),
            findsNothing,
            reason: '"${entry.key}" also read as ${other.$2}',
          );
        }
      });
    }

    testWidgets('a run that ended without reporting claims nothing', (
      tester,
    ) async {
      // The stream closed without an outcome — an error on the way out. Saying
      // "no source has it" here would be inventing the result.
      getIt.registerSingleton<AlternateSourceService>(_Silent());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlternateSourceSheet.withDependencies(
              title: _title,
              provider: 'vidapi',
              category: 'anime',
              episodeNumber: null,
              candidates: const [],
              choices: SourceChoiceStore(box: box),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('player.alt_no_answer'), findsOneWidget);
    });
  });

  group('the words themselves', () {
    test('every string the switcher shows has English text', () {
      final en =
          jsonDecode(
                File('assets/translations/en.json').readAsStringSync(),
              )
              as Map<String, dynamic>;

      String? lookUp(String key) {
        Object? node = en;
        for (final part in key.split('.')) {
          if (node is! Map<String, dynamic>) return null;
          node = node[part];
        }
        return node is String ? node : null;
      }

      final keys = <String>{};
      for (final path in const [
        'lib/features/detail/presentation/widgets/alternate_source_sheet.dart',
        'lib/features/detail/presentation/widgets/source_search_sheet.dart',
      ]) {
        final source = File(path).readAsStringSync();
        for (final m in RegExp(r"'([a-z_]+\.[a-z0-9_]+)'\s*\.tr\(").allMatches(
          source,
        )) {
          keys.add(m.group(1)!);
        }
      }

      // A key with no English text renders as the key itself — "player.alt_guess"
      // in the middle of the row — so this is the only thing standing between a
      // typo and a viewer reading one.
      expect(keys, isNotEmpty, reason: 'the scan found no keys at all');
      for (final key in keys) {
        expect(lookUp(key), isNotNull, reason: '$key has no English text');
      }
    });
  });
}

/// The settings box, in memory.
///
/// A real Hive box is real file I/O, and a widget test runs in fake time: the
/// disk answers on the real event loop, which the test's clock never reaches,
/// so `await box.put(...)` inside a tap handler simply never returns and the
/// correction is never applied. That is not a bug in the store — the app has a
/// real event loop — but it makes a real box unusable here, so the storage is a
/// Map and the futures complete at once.
class _Box implements Box<dynamic> {
  final Map<dynamic, dynamic> entries = {};

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      entries[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) async => entries[key] = value;

  @override
  Future<void> delete(dynamic key) async => entries.remove(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, ProviderSearchResult> _handAnswers() => {
  'an:two': _answer('an:two', 'AniTwo', const [
    'Hwagae Hyeongsa: The Blossoming Blade',
    'Some Other Show',
  ]),
};

/// A search that never finishes, for the frames before any source has spoken.
class _Slow implements AlternateSourceService {
  final StreamController<AlternateSource> _open =
      StreamController<AlternateSource>();

  @override
  Stream<AlternateSource> find({
    required String title,
    required String excludeProvider,
    String titleProvider = '',
    List<ProviderEntity>? candidates,
    void Function(AlternateSearchOutcome outcome)? onOutcome,
  }) => _open.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A run that ends without ever saying how it went.
class _Silent implements AlternateSourceService {
  @override
  Stream<AlternateSource> find({
    required String title,
    required String excludeProvider,
    String titleProvider = '',
    List<ProviderEntity>? candidates,
    void Function(AlternateSearchOutcome outcome)? onOutcome,
  }) async* {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
