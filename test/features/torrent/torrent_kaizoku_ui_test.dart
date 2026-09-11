import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/theme/kaizoku_colors.dart';
import 'package:soplay/features/torrent/domain/entities/release_info.dart';
import 'package:soplay/features/torrent/domain/entities/torrent_result.dart';
import 'package:soplay/features/torrent/presentation/widgets/torrent_result_tile.dart';

void main() {
  group('Torrent Remediated Kaizoku UI Tests', () {
    testWidgets('TorrentResultTile renders healthy torrent and triggers onTap', (tester) async {
      var tapped = false;
      const result = TorrentResult(
        title: '[SubsPlease] One Piece - 1100 (1080p) [12345678].mkv',
        indexerId: 'nyaa',
        indexerName: 'Nyaa',
        seeders: 45,
        leechers: 5,
        sizeBytes: 1468006400,
        release: ReleaseInfo(
          group: 'SubsPlease',
          showTitle: 'One Piece',
          episode: 1100,
          resolutionHeight: 1080,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: KaizokuColors.background,
            body: TorrentResultTile(
              result: result,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.byType(TorrentResultTile), findsOneWidget);
      expect(find.text('[SubsPlease] One Piece - 1100 (1080p) [12345678].mkv'), findsOneWidget);

      await tester.tap(find.byType(TorrentResultTile));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('TorrentResultTile does not trigger onTap when health is dead', (tester) async {
      var tapped = false;
      const deadResult = TorrentResult(
        title: '[DeadGroup] Old Anime - 01 [Dead].mkv',
        indexerId: 'nyaa',
        indexerName: 'Nyaa',
        seeders: 0,
        leechers: 0,
        sizeBytes: 734003200,
        release: ReleaseInfo(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: KaizokuColors.background,
            body: TorrentResultTile(
              result: deadResult,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.byType(TorrentResultTile), findsOneWidget);
      await tester.tap(find.byType(TorrentResultTile));
      await tester.pump();
      expect(tapped, isFalse);
    });
  });
}
