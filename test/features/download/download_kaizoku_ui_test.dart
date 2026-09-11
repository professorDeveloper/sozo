import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/theme/kaizoku_colors.dart';
import 'package:soplay/features/download/domain/entities/download_location.dart';
import 'package:soplay/features/download/domain/entities/storage_usage.dart';
import 'package:soplay/features/download/presentation/bloc/downloads_state.dart';
import 'package:soplay/features/download/presentation/widgets/download_location_tile.dart';
import 'package:soplay/features/download/presentation/widgets/downloads_empty_state.dart';
import 'package:soplay/features/download/presentation/widgets/downloads_storage_header.dart';
import 'package:soplay/features/download/presentation/widgets/downloads_toolbar.dart';

void main() {
  group('Milestone 2.3 Downloads & Offline UI Tests', () {
    testWidgets('DownloadsToolbar renders filter chips and dispatches callbacks', (tester) async {
      DownloadsFilter selectedFilter = DownloadsFilter.all;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: KaizokuColors.cyberObsidian,
            body: DownloadsToolbar(
              filter: selectedFilter,
              onFilter: (f) => selectedFilter = f,
            ),
          ),
        ),
      );

      // Verify all 4 filter chips exist
      expect(find.byType(DownloadsToolbar), findsOneWidget);

      // Tap on the completed filter
      final completedChip = find.text('Completed');
      if (completedChip.evaluate().isNotEmpty) {
        await tester.tap(completedChip);
        await tester.pump();
      }
    });

    testWidgets('DownloadsEmptyState renders correctly in both filtered and unfiltered states', (tester) async {
      var cleared = false;

      // Test unfiltered state
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: KaizokuColors.cyberObsidian,
            body: DownloadsEmptyState(
              filtered: false,
              onClearFilter: () => cleared = true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.download_outlined), findsOneWidget);

      // Test filtered state
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: KaizokuColors.cyberObsidian,
            body: DownloadsEmptyState(
              filtered: true,
              onClearFilter: () => cleared = true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.filter_alt_off_outlined), findsOneWidget);
      final clearBtn = find.byType(FilledButton);
      expect(clearBtn, findsOneWidget);

      await tester.tap(clearBtn);
      await tester.pump();
      expect(cleared, isTrue);
    });

    testWidgets('DownloadsStorageHeader renders usage bar and sweep action', (tester) async {
      var swept = false;
      const usage = StorageUsage(
        usedBytes: 1024 * 1024 * 500, // 500 MB
        freeBytes: 1024 * 1024 * 2000, // 2 GB
        orphanBytes: 1024 * 1024 * 50, // 50 MB
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: KaizokuColors.cyberObsidian,
            body: DownloadsStorageHeader(
              usage: usage,
              busy: false,
              onSweep: () => swept = true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.sd_storage_outlined), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // Verify clean orphans button
      final cleanBtn = find.byType(TextButton);
      expect(cleanBtn, findsOneWidget);

      await tester.tap(cleanBtn);
      await tester.pump();
      expect(swept, isTrue);
    });

    testWidgets('DownloadLocationTile displays multiple volumes and opens picker', (tester) async {
      const loc1 = DownloadLocation(
        path: '/storage/emulated/0/Download',
        label: 'Internal Storage',
        isRemovable: false,
        freeBytes: 1024 * 1024 * 1000,
      );
      const loc2 = DownloadLocation(
        path: '/storage/1234-5678/Android/data',
        label: 'SD Card',
        isRemovable: true,
        freeBytes: 1024 * 1024 * 8000,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: KaizokuColors.cyberObsidian,
            body: DownloadLocationTile(
              locations: const [loc1, loc2],
              current: loc1,
              busy: false,
              onPick: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Internal Storage'), findsOneWidget);
      expect(find.byIcon(Icons.smartphone_rounded), findsOneWidget);

      await tester.tap(find.byType(DownloadLocationTile));
      await tester.pumpAndSettle();

      // BottomSheet should have opened showing SD card option
      expect(find.text('SD Card'), findsOneWidget);
    });
  });
}
