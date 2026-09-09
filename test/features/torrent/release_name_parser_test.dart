import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/torrent/data/release_name_parser.dart';
import 'package:soplay/features/torrent/domain/entities/release_info.dart';

/// Every name below is a real one — taken either from the release-name anatomy
/// documented at <https://wotaku.wiki/torrenting/nyaa> or straight out of a
/// live Nyaa/Tokyo Toshokan feed. Synthetic names would not exercise the parts
/// that actually break: inconsistent separators, metadata in the leading
/// bracket, and ranges that look like episode numbers.
void main() {
  group('bracketed fansub style', () {
    test('parses the wiki\'s canonical SubsPlease example', () {
      final info = ReleaseNameParser.parse(
        '[SubsPlease] Sousou no Frieren S2 - 01 (1080p) [4277EF46].mkv',
      );

      expect(info.group, 'SubsPlease');
      expect(info.showTitle, 'Sousou no Frieren S2');
      expect(info.season, 2);
      expect(info.episode, 1);
      expect(info.resolutionHeight, 1080);
      expect(info.crc32, '4277EF46');
      expect(info.container, 'mkv');
      expect(info.batch, isFalse);
    });

    test('parses a BD encode with explicit dimensions and lossless audio', () {
      final info = ReleaseNameParser.parse(
        '[hydes] Akira (BDRip 1920x1032 x264 FLAC).mkv',
      );

      expect(info.group, 'hydes');
      // 1032 is a cropped scope height; it snaps to the 1080p tier so a
      // ">= 1080p" filter still keeps it.
      expect(info.resolutionHeight, 1080);
      expect(info.source, ReleaseSource.bluRayEncode);
      expect(info.codec, VideoCodec.h264);
      expect(info.audio, contains(AudioFormat.flac));
    });

    test('reads HEVC, multi-sub and the CRC from an Erai-raws name', () {
      final info = ReleaseNameParser.parse(
        '[Erai-raws] buchigire - 08 [1080p CR WEBRip HEVC AAC][MultiSub][FBCB78C6].mkv',
      );

      expect(info.group, 'Erai-raws');
      expect(info.episode, 8);
      expect(info.resolutionHeight, 1080);
      expect(info.source, ReleaseSource.webRip);
      expect(info.codec, VideoCodec.h265);
      expect(info.audio, contains(AudioFormat.aac));
      expect(info.multiSubtitle, isTrue);
      expect(info.crc32, 'FBCB78C6');
    });

    test('detects dual audio and HDR', () {
      final info = ReleaseNameParser.parse(
        "[Salieri] Frieren - Beyond Journey's End S2 - BD (1080p) (HDR) [Dual Audio]",
      );

      expect(info.group, 'Salieri');
      expect(info.season, 2);
      expect(info.source, ReleaseSource.bluRayEncode);
      expect(info.hdr, isTrue);
      expect(info.dualAudio, isTrue);
    });
  });

  group('scene / dotted style', () {
    test('parses the wiki\'s VARYG example', () {
      final info = ReleaseNameParser.parse(
        'Frieren.Beyond.Journeys.End.S02E01.Shall.We.Go.Then.1080p.CR.WEB-DL.MULTi.AAC2.0.H.264-VARYG.mkv',
      );

      expect(info.group, 'VARYG');
      expect(info.season, 2);
      expect(info.episode, 1);
      expect(info.resolutionHeight, 1080);
      expect(info.source, ReleaseSource.webDl);
      expect(info.codec, VideoCodec.h264);
      expect(info.audio, contains(AudioFormat.aac));
      expect(info.container, 'mkv');
    });
  });

  group('quality signals the filters depend on', () {
    test('flags mini-encodes, which are excluded by default', () {
      final info = ReleaseNameParser.parse(
        '[Judas] Attack on Titan S4 - 01 [1080p][HEVC x265 10bit][Mini-Encode]',
      );

      expect(info.source, ReleaseSource.miniEncode);
      expect(info.bitDepth, 10);
      expect(info.codec, VideoCodec.h265);
    });

    test('remux outranks a bare BD tag in the same name', () {
      final info = ReleaseNameParser.parse('Perfect.Blue.1997.BD.Remux.1080p.FLAC');
      expect(info.source, ReleaseSource.remux);
    });

    test('EAC3 is not misread as AC3', () {
      final info = ReleaseNameParser.parse('Show.S01E01.1080p.WEB-DL.EAC3.5.1.H.265-GRP');
      expect(info.audio, contains(AudioFormat.eac3));
      expect(info.audio, isNot(contains(AudioFormat.ac3)));
    });

    test('Hi10P counts as 10-bit', () {
      final info = ReleaseNameParser.parse('[Coalgirls] Show 01 (1920x1080 Hi10P FLAC)');
      expect(info.bitDepth, 10);
    });

    test('an mp4 anime release is treated as hardsubbed', () {
      // MP4 cannot carry the ASS tracks fansubs use, so the subs are burned in.
      final info = ReleaseNameParser.parse('[Group] Show - 05 (720p).mp4');
      expect(info.container, 'mp4');
      expect(info.hasHardsubs, isTrue);
    });
  });

  group('batches', () {
    test('an episode range is a batch, not episode 1', () {
      final info = ReleaseNameParser.parse('[Judas] Vinland Saga S2 - 01-24 [1080p][BATCH]');

      expect(info.episode, 1);
      expect(info.episodeEnd, 24);
      expect(info.batch, isTrue);
    });

    test('the word "Complete" alone marks a batch', () {
      final info = ReleaseNameParser.parse('[Group] Show Complete Series (1080p BD)');
      expect(info.batch, isTrue);
    });
  });

  group('robustness', () {
    test('a leading date bracket is metadata, not a release group', () {
      // Common on Sukebei: [250209][Artist] Title
      final info = ReleaseNameParser.parse('[250209][Shiina Ecchigawa] Some Title');
      expect(info.group, isNot('250209'));
    });

    test('a trailing resolution is not mistaken for a scene group', () {
      final info = ReleaseNameParser.parse('Some.Movie.2019.WEB-DL-1080p');
      expect(info.group, isNull);
    });

    test('never throws on junk', () {
      for (final name in ['', '   ', '[[[', '磁力链接', '....mkv', '-']) {
        expect(() => ReleaseNameParser.parse(name), returnsNormally);
      }
    });
  });
}
