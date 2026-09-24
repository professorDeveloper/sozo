// No translations are loaded, so every `.tr()` renders as its own key.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/download/domain/entities/downloaded_title.dart';
import 'package:soplay/features/download/presentation/widgets/downloaded_titles_grid.dart';
import 'package:soplay/features/download/presentation/widgets/downloads_view_switch.dart';
import 'package:soplay/features/download/presentation/widgets/offline_copy_banner.dart';

import 'offline_fakes.dart';

void main() {
  testWidgets('one poster per title, opening and acting on it', (tester) async {
    final titles = DownloadedTitle.group([episode(1), episode(2), movie()]);
    DownloadedTitle? opened;
    DownloadedTitle? acted;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              DownloadedTitlesGrid(
                titles: titles,
                thumbnailOf: (_) => null,
                providerNameOf: (_) => 'Old Source',
                onOpen: (t) => opened = t,
                onActions: (t) => acted = t,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Show'), findsOneWidget);
    expect(find.text('Film'), findsOneWidget);
    expect(find.text('downloads.title_movie · Old Source'), findsOneWidget);

    await tester.tap(find.text('Show'));
    await tester.pump();
    // The caption is outside the poster's tap target; the poster opens.
    expect(opened, isNull);
    await tester.tap(find.byType(InkWell).first);
    await tester.pump();
    expect(opened, isNotNull);

    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pump();
    expect(acted, isNotNull);
  });

  testWidgets('the view switch reports the other view', (tester) async {
    DownloadsView? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DownloadsViewSwitch(
            view: DownloadsView.titles,
            onChanged: (v) => picked = v,
          ),
        ),
      ),
    );
    await tester.tap(find.text('downloads.view_files'));
    expect(picked, DownloadsView.files);
  });

  testWidgets('the offline banner offers a retry only when given one', (
    tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              OfflineCopyBanner(
                message: 'saved words',
                onRetry: () => retried = true,
              ),
              const OfflineCopyBanner(message: 'no retry'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('detail.offline_copy'), findsNWidgets(2));
    expect(find.text('general.retry'), findsOneWidget);
    await tester.tap(find.text('general.retry'));
    expect(retried, isTrue);
  });
}
