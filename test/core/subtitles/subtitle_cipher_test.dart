// KissKH `.srt.txt1` tracks: AES-128-CBC cue text, per docs/SUBTITLE_CIPHER.md.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/subtitles/subtitle_cipher.dart';
import 'package:soplay/core/subtitles/subtitle_parser.dart';
import 'package:soplay/features/detail/data/models/subtitle_model.dart';
import 'package:soplay/features/detail/domain/entities/subtitle_entity.dart';
import 'package:soplay/features/download/data/subtitle_sidecar.dart';

const kisskh = SubtitleCipher(
  alg: 'aes-128-cbc',
  key: 'AmSmZVcH93UQUezi',
  iv: 'ReBKWW8cqdjPEnF6',
);

// The head of Revenged Love Ep1 (English) as the CDN serves it.
const ciphered =
    '1\r\n00:00:17,152 --> 00:00:19,208\r\n'
    'Sq/yslS8glo0CoTCWZBT0GepZqSNY4KqATqtSAO1798=\r\n\r\n'
    '2\r\n00:00:19,968 --> 00:00:23,584\r\n'
    '8eGx+aPSbxKlXGJ6GNMb7lwpbp4jM4y1/LLyz3X0TgP/ogC0dl/OB+meqM2DBows\r\n\r\n'
    '3\r\n00:00:23,584 --> 00:00:28,907\r\n'
    'pNx/wGy5Ujioalb4vL7Avv1y7G3gcz9kBHuyjHRWCdGsT56/mF1Oz2kbnUoys2H7SzHzM/xvHGymaa10KzUKUw==\r\n\r\n';

void main() {
  test('the documented test vector', () async {
    expect(
      await kisskh.decrypt('Sq/yslS8glo0CoTCWZBT0GepZqSNY4KqATqtSAO1798='),
      '<i>♫ Set off ♫</i>',
    );
  });

  test('a real file decrypts and parses, structure untouched', () async {
    final plain = await kisskh.decrypt(ciphered);
    expect(
      plain,
      contains('1\r\n00:00:17,152 --> 00:00:19,208\r\n<i>♫ Set off ♫</i>\r\n'),
    );
    final cues = parseSubtitleBytes(
      await kisskh.decryptBytes(utf8.encode(ciphered)),
      url: 'https://sub.cdnvideo11.shop/x.en.srt.txt1?v=1',
    ).captions;
    expect(cues.map((c) => c.text), [
      '♫ Set off ♫',
      '♫ With the latte I just brewed ♫',
      '♫ And the long-lost sunshine in early summer ♫',
    ]);
    expect(cues.first.start, const Duration(seconds: 17, milliseconds: 152));
  });

  test('a line that will not open is kept, the rest still decrypt', () async {
    final out = await kisskh.decrypt(
      '${ciphered}4\n00:00:30,000 --> 00:00:31,000\nplain words\n',
    );
    expect(out, contains('plain words'));
    expect(out, contains('<i>♫ Set off ♫</i>'));
  });

  test('a wrong key or an unknown cipher fails the track', () async {
    const wrong = SubtitleCipher(
      alg: 'aes-128-cbc',
      key: 'AAAAAAAAAAAAAAAA',
      iv: 'ReBKWW8cqdjPEnF6',
    );
    await expectLater(
      wrong.decrypt(ciphered),
      throwsA(isA<SubtitleCipherException>()),
    );
    const other = SubtitleCipher(alg: 'aes-256-gcm', key: 'k', iv: 'i');
    expect(other.isSupported, isFalse);
    await expectLater(
      other.decrypt(ciphered),
      throwsA(isA<SubtitleCipherException>()),
    );
  });

  test('the model reads the cipher and only a complete one', () {
    final sub = SubtitleModel.fromJson({
      'label': 'English',
      'src': 'https://sub.cdnvideo11.shop/a.en.srt.txt1',
      'cipher': {
        'alg': 'aes-128-cbc',
        'key': 'AmSmZVcH93UQUezi',
        'iv': 'ReBKWW8cqdjPEnF6',
        'scope': 'cue-text',
        'encoding': 'base64',
      },
    });
    expect(sub.file, endsWith('.txt1'));
    expect(sub.cipher!.isSupported, isTrue);
    expect(SubtitleModel.fromJson({'file': 'a.srt'}).cipher, isNull);
    expect(SubtitleCipher.fromJson({'alg': 'aes-128-cbc', 'key': ''}), isNull);
    expect(SubtitleCipher.fromJson('aes'), isNull);
  });

  test('a downloaded ciphered track is kept decrypted', () async {
    final root = await Directory.systemTemp.createTemp('sozo_cipher_root_');
    final src = await Directory.systemTemp.createTemp('sozo_cipher_src_');
    addTearDown(() async {
      await root.delete(recursive: true);
      await src.delete(recursive: true);
    });
    final f = File('${src.path}/a.en.srt.txt1')..writeAsStringSync(ciphered);
    final sidecar = SubtitleSidecar(root: () async => root);
    await sidecar.save('ep', [
      SubtitleEntity(label: 'English', file: f.path, cipher: kisskh),
    ]);
    final back = await sidecar.load('ep');
    expect(back.single.file, endsWith('.srt'));
    expect(back.single.cipher, isNull);
    expect(await File(back.single.file).readAsString(), contains('Set off'));
  });
}
