// The servers page opened on a red screen until a server was saved: the
// store answers `const []` for none, and the page sorted it in place.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/features/jellyfin/data/jellyfin_server_store.dart';
import 'package:soplay/features/jellyfin/presentation/pages/jellyfin_servers_page.dart';

import 'jellyfin_fakes.dart';

void main() {
  setUp(() async {
    await getIt.reset();
    getIt.registerSingleton<JellyfinServerStore>(
      JellyfinServerStore(box: () => null),
    );
  });
  tearDown(() => getIt.reset());

  testWidgets('with no servers, and with some', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: JellyfinServersPage()));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await getIt<JellyfinServerStore>().save(testServer);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
