// A download's subtitles, kept beside it and read back offline.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/entities/subtitle_entity.dart';
import 'package:soplay/features/download/data/subtitle_sidecar.dart';

void main() {
  late Directory root;
  late Directory src;
  late SubtitleSidecar sidecar;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sozo_sidecar_root_');
    src = await Directory.systemTemp.createTemp('sozo_sidecar_src_');
    sidecar = SubtitleSidecar(root: () async => root);
  });

  tearDown(() async {
    await root.delete(recursive: true);
    await src.delete(recursive: true);
  });

  Future<SubtitleEntity> track(String label, String name, String body) async {
    final f = File('${src.path}/$name');
    await f.writeAsString(body);
    return SubtitleEntity(label: label, file: f.path);
  }

  test('kept tracks come back as files, the one on screen first', () async {
    final en = await track(
      'English',
      'en.srt',
      '1\n00:00:01,000 --> 00:00:02,000\nHi\n',
    );
    final fr = await track(
      'French',
      'fr.vtt',
      'WEBVTT\n\n00:01.000 --> 00:02.000\nSalut\n',
    );
    const ai = SubtitleEntity(label: "O'zbekcha [AI]", file: 'ai:uz');
    final kept = await sidecar.save('ep1', [en, fr, ai], active: 1);
    expect(kept, 2);

    final back = await sidecar.load('ep1');
    expect(back.map((t) => t.label), ['French', 'English']);
    expect(back.first.isDefault, isTrue);
    expect(back.first.file, endsWith('.vtt'));
    expect(await File(back.last.file).readAsString(), contains('Hi'));
  });

  test('nothing kept reads as nothing, and delete removes it', () async {
    expect(await sidecar.load('none'), isEmpty);
    final en = await track('English', 'en.srt', 'x');
    await sidecar.save('ep2', [en]);
    expect(await sidecar.load('ep2'), hasLength(1));
    await sidecar.delete('ep2');
    expect(await sidecar.load('ep2'), isEmpty);
  });
}
