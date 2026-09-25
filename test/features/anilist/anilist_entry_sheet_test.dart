import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';
import 'package:soplay/features/anilist/presentation/controllers/anilist_library_controller.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_entry_sheet.dart';

/// The entry sheet, opened on a library that holds both halves of AniList.
///
/// No translations are loaded, so every `.tr()` renders as its own key. That is
/// deliberate: it makes these assertions about WHICH caption the sheet chose
/// rather than about its current wording. That the keys exist, and read as
/// English, is asserted separately at the bottom of this file against
/// `assets/translations/en.json`.
void main() {
  group('what the count is measured in', () {
    testWidgets('a manga shows its chapter total and a chapter caption', (
      tester,
    ) async {
      await _open(tester, _entry(_manga(chapters: 100), progress: 3));

      expect(find.text('3 / 100'), findsOneWidget);
      expect(find.text('anilist.chapters_read'), findsOneWidget);
      expect(find.text('anilist.episodes_watched'), findsNothing);
    });

    testWidgets('an anime is unchanged: episode total, episode caption', (
      tester,
    ) async {
      await _open(tester, _entry(_anime(episodes: 12), progress: 5));

      expect(find.text('5 / 12'), findsOneWidget);
      expect(find.text('anilist.episodes_watched'), findsOneWidget);
      expect(find.text('anilist.chapters_read'), findsNothing);
    });

    testWidgets('a light novel is read, not watched', (tester) async {
      await _open(
        tester,
        _entry(_manga(chapters: 40, format: 'NOVEL'), progress: 1),
      );

      expect(find.text('1 / 40'), findsOneWidget);
      expect(find.text('anilist.chapters_read'), findsOneWidget);
    });

    testWidgets('a serial with no announced total still says chapters', (
      tester,
    ) async {
      await _open(tester, _entry(_manga(chapters: null), progress: 214));

      expect(find.text('214'), findsOneWidget);
      expect(find.text('anilist.chapters_read'), findsOneWidget);
    });
  });

  group('the keys the sheet asks for', () {
    test('both captions exist in English', () {
      final anilist =
          (jsonDecode(
                File('assets/translations/en.json').readAsStringSync(),
              )
              as Map<String, dynamic>)['anilist'] as Map<String, dynamic>;

      expect(anilist['episodes_watched'], 'episodes watched');
      expect(
        anilist['chapters_read'],
        'chapters read',
        reason:
            'the caption under a reader\'s count, and the one thing on the '
            'sheet that says the number is not episodes',
      );
    });
  });
}

Future<void> _open(WidgetTester tester, AnilistListEntry entry) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AnilistEntrySheet(
          entryId: entry.id,
          controller: _Library([entry]),
        ),
      ),
    ),
  );
  await tester.pump();
}

AnilistListEntry _entry(AnilistMedia media, {required int progress}) =>
    AnilistListEntry(
      id: 991,
      media: media,
      status: AnilistStatus.current.value,
      progress: progress,
    );

/// Covers are left null on purpose: a URL would send the widget to the network,
/// which a widget test has no answer for.
AnilistMedia _manga({required int? chapters, String? format}) => AnilistMedia(
  id: 1,
  romajiTitle: 'Berserk',
  type: 'MANGA',
  chapters: chapters,
  format: format ?? 'MANGA',
);

AnilistMedia _anime({required int episodes}) => AnilistMedia(
  id: 2,
  romajiTitle: 'Cowboy Bebop',
  type: 'ANIME',
  episodes: episodes,
  format: 'TV',
);

/// A library that is simply handed its entries, with nothing in flight.
///
/// The sheet only ever reads the controller — it re-reads the entry on every
/// build rather than holding one — so overriding what it reads is enough to
/// draw any entry without an AniList account behind it.
class _Library extends AnilistLibraryController {
  _Library(this._entries) : super(service: _Service());

  final List<AnilistListEntry> _entries;

  @override
  List<AnilistListEntry> get entries => _entries;

  @override
  bool isBusy(int entryId) => false;
}

/// Never touched: the controller stores the service, and nothing the sheet
/// draws goes near it.
class _Service implements AnilistService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
