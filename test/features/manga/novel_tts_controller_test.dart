import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/manga/data/tts/tts_engine.dart';
import 'package:soplay/features/manga/presentation/tts/novel_tts_controller.dart';
import 'package:soplay/features/manga/presentation/widgets/novel_text.dart';

import 'fake_tts_engine.dart';

class MemoryPrefs implements TtsPreferences {
  @override
  double rate = 1.0;
  @override
  double pitch = 1.0;
  @override
  bool autoNext = true;
  final voices = <String, String>{};

  @override
  String? voiceFor(String lang) => voices[lang];

  @override
  void setVoiceFor(String lang, String? name) =>
      name == null ? voices.remove(lang) : voices[lang] = name;
}

const _chapter1 = '<h2>Chapter 1</h2><hr><p>One. Two.</p><p>Three.</p>';
const _chapter2 = '<p>Four. Five.</p>';

void main() {
  late FakeEngine engine;
  late MemoryPrefs prefs;
  late NovelTtsController tts;

  setUp(() {
    engine = FakeEngine();
    prefs = MemoryPrefs();
    tts = NovelTtsController(engine: engine, prefs: prefs);
  });

  tearDown(() => tts.dispose());

  Future<void> settle() => pumpEventQueue();

  test('reads a chapter sentence by sentence, then goes idle', () async {
    tts.setAutoNext(false);
    tts.setChapter(parseNovelBlocks(_chapter1));
    await tts.play();
    await settle();
    expect(tts.status, TtsStatus.playing);
    expect(tts.current?.text, 'Chapter 1');
    for (var i = 0; i < 4; i++) {
      engine.finish();
      await settle();
    }
    expect(engine.spoken, ['Chapter 1', 'One.', 'Two.', 'Three.']);
    expect(tts.status, TtsStatus.idle);
  });

  test('pause stops the engine; resume says the same sentence again', () async {
    tts.setChapter(parseNovelBlocks(_chapter1));
    await tts.play(from: 1);
    await settle();
    expect(engine.spoken.last, 'One.');
    tts.pause();
    await settle();
    expect(tts.status, TtsStatus.paused);
    expect(tts.current?.text, 'One.');
    expect(engine.calls, contains('stop'));
    tts.resume();
    await settle();
    expect(engine.spoken, ['One.', 'One.']);
    expect(tts.status, TtsStatus.playing);
  });

  test('next and previous move by sentence while playing', () async {
    tts.setChapter(parseNovelBlocks(_chapter1));
    await tts.play();
    await settle();
    tts.next();
    await settle();
    expect(engine.spoken.last, 'One.');
    tts.next();
    await settle();
    expect(engine.spoken.last, 'Two.');
    tts.previous();
    await settle();
    expect(engine.spoken.last, 'One.');
  });

  test('a new speed is saved and the sentence is said again at it', () async {
    tts.setChapter(parseNovelBlocks(_chapter1));
    await tts.play(from: 2);
    await settle();
    await tts.setRate(1.5);
    await settle();
    expect(prefs.rate, 1.5);
    expect(engine.calls, contains('rate 1.5'));
    expect(engine.spoken, ['Two.', 'Two.']);
  });

  test('the spoken position is reported in thousandths', () async {
    tts.setChapter(parseNovelBlocks('<p>Aaaa.</p><p>Bbbb.</p>'));
    await tts.play();
    await settle();
    expect(tts.spokenPermille, 0);
    engine.finish();
    await settle();
    expect(tts.spokenPermille, 500);
  });

  group('auto-continue', () {
    test('waits for the next chapter, then reads it', () async {
      final next = Completer<TtsChapter?>();
      tts.onChapterEnd = () => next.future;
      tts.setChapter(parseNovelBlocks('<p>Last.</p>'));
      await tts.play();
      await settle();
      engine.finish();
      await settle();
      expect(tts.status, TtsStatus.loading);
      // Pause is refused while the next chapter is on its way: resuming
      // would ask for the one after it.
      tts.pause();
      expect(tts.status, TtsStatus.loading);
      next.complete(
        TtsChapter(parseNovelBlocks(_chapter2), preface: 'Chapter 2'),
      );
      await settle();
      expect(tts.status, TtsStatus.playing);
      expect(engine.spoken, ['Last.', 'Chapter 2']);
      engine.finish();
      await settle();
      expect(engine.spoken.last, 'Four.');
    });

    test('stops cleanly when there is no next chapter', () async {
      tts.onChapterEnd = () async => null;
      tts.setChapter(parseNovelBlocks('<p>Last.</p>'));
      await tts.play();
      await settle();
      engine.finish();
      await settle();
      expect(tts.status, TtsStatus.idle);
    });

    test('a next chapter that throws or is empty stops too', () async {
      tts.onChapterEnd = () async => throw Exception('403');
      tts.setChapter(parseNovelBlocks('<p>Last.</p>'));
      await tts.play();
      await settle();
      engine.finish();
      await settle();
      expect(tts.status, TtsStatus.idle);

      tts.onChapterEnd = () async => const TtsChapter([]);
      tts.setChapter(parseNovelBlocks('<p>Last.</p>'));
      await tts.play();
      await settle();
      engine.finish();
      await settle();
      expect(tts.status, TtsStatus.idle);
    });

    test('off in settings means the chapter end is the end', () async {
      var asked = false;
      tts.onChapterEnd = () async {
        asked = true;
        return null;
      };
      tts.setAutoNext(false);
      expect(prefs.autoNext, isFalse);
      tts.setChapter(parseNovelBlocks('<p>Last.</p>'));
      await tts.play();
      await settle();
      engine.finish();
      await settle();
      expect(asked, isFalse);
      expect(tts.status, TtsStatus.idle);
    });
  });

  group('sleep timer', () {
    test('stops after the sentence in progress once time is up', () {
      fakeAsync((async) {
        final notices = <TtsNotice>[];
        tts.onNotice = notices.add;
        tts.setChapter(parseNovelBlocks(_chapter1));
        tts.play();
        async.flushMicrotasks();
        tts.setSleep(15);
        async.elapse(const Duration(minutes: 15));
        // Still speaking: the timer does not cut a sentence in half.
        expect(tts.status, TtsStatus.playing);
        engine.finish();
        async.flushMicrotasks();
        expect(tts.status, TtsStatus.idle);
        expect(tts.sleepMinutes, 0);
        expect(notices, [TtsNotice.sleepStopped]);
        expect(engine.spoken, ['Chapter 1']);
      });
    });

    test('"end of chapter" does not ask for the next one', () async {
      var asked = false;
      tts.onChapterEnd = () async {
        asked = true;
        return TtsChapter(parseNovelBlocks(_chapter2));
      };
      tts.setChapter(parseNovelBlocks('<p>Last.</p>'));
      tts.setSleep(NovelTtsController.sleepEndOfChapter);
      await tts.play();
      await settle();
      engine.finish();
      await settle();
      expect(asked, isFalse);
      expect(tts.status, TtsStatus.idle);
    });

    test('turning it off cancels it', () {
      fakeAsync((async) {
        tts.setChapter(parseNovelBlocks(_chapter1));
        tts.play();
        async.flushMicrotasks();
        tts.setSleep(15);
        tts.setSleep(0);
        async.elapse(const Duration(minutes: 20));
        engine.finish();
        async.flushMicrotasks();
        expect(tts.status, TtsStatus.playing);
        expect(tts.sleepEndsAt, isNull);
      });
    });
  });

  group('voices', () {
    const ru1 = TtsVoice(name: 'ru-ru-x-dfc-local', locale: 'ru-RU');
    const ru2 = TtsVoice(name: 'ru-ru-x-ruc-network', locale: 'ru-RU');
    const en = TtsVoice(name: 'en-us-x-iol-local', locale: 'en-US');

    test('only the language\'s voices are offered, local first', () async {
      engine.voiceList = const [ru2, en, ru1];
      await tts.setLanguage('ru');
      expect(tts.voices, [ru1, ru2]);
      expect(tts.voice, isNull);
    });

    test('the saved voice for the language comes back', () async {
      prefs.voices['ru'] = ru2.name;
      engine.voiceList = const [ru1, ru2, en];
      await tts.setLanguage('ru');
      expect(tts.voice, ru2);
      tts.setChapter(parseNovelBlocks('<p>Привет.</p>'));
      await tts.play();
      await settle();
      expect(
        engine.calls,
        containsAllInOrder(['lang ru-RU', 'voice ${ru2.name}']),
      );
    });

    test('choosing a voice saves it per language', () async {
      engine.voiceList = const [ru1, ru2];
      await tts.setLanguage('ru');
      await tts.setVoice(ru1);
      expect(prefs.voices['ru'], ru1.name);
      await tts.setVoice(null);
      expect(prefs.voices.containsKey('ru'), isFalse);
    });

    test(
      'no voice for the language is reported, and reading goes on',
      () async {
        final notices = <TtsNotice>[];
        tts.onNotice = notices.add;
        await tts.setLanguage('uz');
        tts.setChapter(parseNovelBlocks('<p>Salom.</p>'));
        await tts.play();
        await settle();
        expect(notices, [TtsNotice.noVoiceForLanguage]);
        expect(engine.spoken, ['Salom.']);
      },
    );
  });

  test('an engine that keeps failing is given up on, with a notice', () async {
    final notices = <TtsNotice>[];
    tts.onNotice = notices.add;
    engine.failEverything = true;
    tts.setChapter(parseNovelBlocks(_chapter1));
    await tts.play();
    await settle();
    expect(tts.status, TtsStatus.idle);
    expect(engine.spoken.length, 3);
    expect(notices, [TtsNotice.failed]);
  });

  test('a new chapter replaces the old one and stops reading', () async {
    tts.setChapter(parseNovelBlocks(_chapter1));
    await tts.play();
    await settle();
    tts.setChapter(parseNovelBlocks(_chapter2));
    expect(tts.status, TtsStatus.idle);
    expect(tts.index, 0);
    engine.finish();
    await settle();
    expect(engine.spoken, ['Chapter 1']);
  });
}
