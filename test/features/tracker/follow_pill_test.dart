// The chevron on a followed title's pill promises a menu; tapping it must not
// unfollow.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/detail/domain/entities/detail_entity.dart';
import 'package:soplay/features/detail/domain/usecases/get_episodes_usecase.dart';
import 'package:soplay/features/notifications/data/services/notification_service.dart';
import 'package:soplay/features/tracker/data/follow_service.dart';
import 'package:soplay/features/tracker/domain/entities/followed_title.dart';
import 'package:soplay/features/tracker/presentation/widgets/follow_bell.dart';

class _Hive implements HiveService {
  List<Map<String, dynamic>> raw = [];

  @override
  List<Map<String, dynamic>> getFollowedRaw() =>
      raw.map((e) => Map<String, dynamic>.from(e)).toList();

  @override
  Future<void> setFollowedRaw(List<Map<String, dynamic>> items) async =>
      raw = items;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Episodes implements GetEpisodesUseCase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Notifications implements NotificationService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _detail = DetailEntity(
  provider: 'p',
  contentId: '1',
  contentUrl: 'https://p.test/show',
  title: 'Show',
  description: '',
  thumbnail: '',
  year: 2020,
  duration: null,
  country: null,
  director: null,
  genres: [],
  cast: [],
  likes: 0,
  dislikes: 0,
  isSerial: true,
  isFavorited: false,
  screenshots: [],
  related: [],
);

void main() {
  late FollowService follows;

  setUp(() async {
    await getIt.reset();
    follows = FollowService(
      hive: _Hive(),
      getEpisodes: _Episodes(),
      notifications: _Notifications(),
    );
    getIt.registerSingleton<FollowService>(follows);
    await follows.follow(
      const FollowedTitle(
        contentUrl: 'https://p.test/show',
        provider: 'p',
        title: 'Show',
        thumbnail: '',
      ),
    );
  });
  tearDown(() => getIt.reset());

  testWidgets('tapping a followed pill opens the menu, not an unfollow', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: FollowBellPill(detail: _detail))),
      ),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.expand_more_rounded));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(follows.isFollowed(_detail.contentUrl), isTrue);
    expect(find.byType(SwitchListTile), findsOneWidget);
  });
}
