// A comment that could not be posted is not thrown away.
//
// The compose box cleared the instant Send was pressed — before the request had
// even been issued, because the panel only adds an event to the bloc and
// returns immediately. When the write then failed, a snackbar said so over an
// empty box, and something somebody had spent a minute writing was gone with no
// way to get it back.
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/auth/data/models/user_model.dart';
import 'package:soplay/features/comments/domain/entities/comment_author.dart';
import 'package:soplay/features/comments/domain/entities/comment_entity.dart';
import 'package:soplay/features/comments/domain/entities/comment_list.dart';
import 'package:soplay/features/comments/domain/repositories/comments_repository.dart';
import 'package:soplay/features/comments/presentation/blocs/comments_bloc/comments_bloc.dart';
import 'package:soplay/features/comments/presentation/widgets/comments_panel.dart';

class _Translations extends AssetLoader {
  const _Translations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

/// An empty thread whose `create` fails or succeeds on command.
class _Repo implements CommentsRepository {
  bool createFails = true;
  final posted = <String>[];

  @override
  Future<Result<CommentList>> getComments({
    required String provider,
    required String contentUrl,
    int page = 1,
    int limit = 20,
  }) async => Success(
    const CommentList(items: [], page: 1, totalPages: 1, total: 0),
  );

  @override
  Future<Result<CommentEntity>> create({
    required String provider,
    required String contentUrl,
    required String text,
    String? parentId,
  }) async {
    posted.add(text);
    if (createFails) {
      return Failure(Exception('SocketException: Failed host lookup'));
    }
    final now = DateTime.now();
    return Success(
      CommentEntity(
        id: 'new',
        provider: provider,
        contentUrl: contentUrl,
        text: text,
        parentId: parentId,
        user: const CommentAuthor(id: 'u1', username: 'me'),
        likeCount: 0,
        likedByMe: false,
        edited: false,
        replyCount: 0,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _SignedIn implements HiveService {
  @override
  bool get isLoggedIn => true;

  @override
  UserModel? getUser() => UserModel(id: 'u1', username: 'me', email: 'a@b.c');

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  late _Repo repo;

  setUp(() async {
    await getIt.reset();
    repo = _Repo();
    getIt.registerFactory<CommentsBloc>(
      () => CommentsBloc(repository: repo, hiveService: _SignedIn()),
    );
  });

  tearDown(() async => getIt.reset());

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        startLocale: const Locale('en'),
        path: 'assets/translations',
        assetLoader: const _Translations(),
        saveLocale: false,
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: const Scaffold(
              body: CommentsPanel(
                provider: 'src',
                contentUrl: 'https://example.test/thing',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> typeAndSend(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    // The send control is the only icon button in the compose row.
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
  }

  const draft = 'A long thought about episode twelve';

  testWidgets('a post that fails leaves the words in the box', (tester) async {
    await pumpPanel(tester);

    await typeAndSend(tester, draft);

    expect(repo.posted, [draft], reason: 'it was genuinely attempted');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      draft,
      reason:
          'the box cleared on Send and the failure arrived over an empty one, '
          'so the comment was simply lost',
    );
  });

  testWidgets('and the reason is still shown', (tester) async {
    // The restore must not swallow the snackbar that explains the failure.
    await pumpPanel(tester);

    await typeAndSend(tester, draft);

    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('sending again works, and then the box clears', (tester) async {
    // The other half. If the draft were held forever the box would refill
    // after a successful post, and the next comment would start with the last
    // one already in it.
    await pumpPanel(tester);
    await typeAndSend(tester, draft);
    // Let the failure's snackbar go: it sits over the send control, and the
    // viewer pressing Send again is a second or two later anyway.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    repo.createFails = false;
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(repo.posted, [draft, draft]);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('a post that works does not put anything back', (tester) async {
    repo.createFails = false;
    await pumpPanel(tester);

    await typeAndSend(tester, draft);

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });
}
