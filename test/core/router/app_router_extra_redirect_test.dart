import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/router/app_router.dart';
import 'package:soplay/features/detail/domain/entities/episodes_args.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';
import 'package:soplay/features/detail/presentation/pages/actor_page.dart';
import 'package:soplay/features/manga/domain/entities/reader_args.dart';

final _typed = <String, Object>{
  '/player': const PlayerArgs(title: 't', provider: 'p', headers: {}),
  '/reader': const ReaderArgs(
    title: 't',
    provider: 'p',
    contentUrl: 'u',
    chapters: [],
    initialChapterIndex: 0,
  ),
  '/episodes': const EpisodesArgs(title: 't', episodes: []),
  '/actor': const ActorArgs(name: 'n'),
};

GoRouterState _state(String path, Object? extra) => GoRouterState(
  AppRouter.router.configuration,
  uri: Uri.parse(path),
  matchedLocation: path,
  path: path,
  fullPath: path,
  pathParameters: const {},
  extra: extra,
  pageKey: ValueKey<String>(path),
);

GoRoute _route(String path) => AppRouter.router.configuration.routes
    .whereType<GoRoute>()
    .firstWhere((r) => r.path == path);

void main() {
  testWidgets('routes that need an extra go Home without one', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox.shrink();
        },
      ),
    );

    for (final entry in _typed.entries) {
      final redirect = _route(entry.key).redirect;
      expect(redirect, isNotNull, reason: entry.key);
      expect(
        await redirect!(context, _state(entry.key, null)),
        '/main',
        reason: '${entry.key} with no extra',
      );
      expect(
        await redirect(context, _state(entry.key, 'wrong type')),
        '/main',
        reason: '${entry.key} with the wrong extra',
      );
      expect(
        await redirect(context, _state(entry.key, entry.value)),
        isNull,
        reason: '${entry.key} with its args',
      );
    }
  });
}
