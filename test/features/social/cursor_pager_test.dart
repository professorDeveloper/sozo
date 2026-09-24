import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/social/domain/social_models.dart';
import 'package:soplay/features/social/presentation/cursor_pager.dart';

void main() {
  CursorPager<String> pager(Map<String?, CursorPage<String>> pages) =>
      CursorPager<String>(
        fetch: (cursor) async =>
            pages[cursor] ?? (throw StateError('no page $cursor')),
        idOf: (s) => s,
      );

  test(
    'refresh loads the first page and loadMore follows the cursor',
    () async {
      final p = pager({
        null: const CursorPage(['a', 'b'], 'c1'),
        'c1': const CursorPage(['c'], null),
      });
      await p.refresh();
      expect(p.items, ['a', 'b']);
      expect(p.hasMore, isTrue);

      await p.loadMore();
      expect(p.items, ['a', 'b', 'c']);
      expect(p.hasMore, isFalse);

      await p.loadMore();
      expect(p.items, ['a', 'b', 'c'], reason: 'no cursor, no request');
    },
  );

  test('an entry that moved to a later page is shown once', () async {
    final p = pager({
      null: const CursorPage(['a', 'b'], 'c1'),
      'c1': const CursorPage(['b', 'c'], null),
    });
    await p.refresh();
    await p.loadMore();
    expect(p.items, ['a', 'b', 'c']);
  });

  test('a repeated cursor ends paging instead of looping', () async {
    final p = pager({
      null: const CursorPage(['a'], 'c1'),
      'c1': const CursorPage(['a'], 'c1'),
    });
    await p.refresh();
    await p.loadMore();
    expect(p.hasMore, isFalse);
  });

  test('a failed first load is an error, not an empty list', () async {
    final p = pager({});
    await p.refresh();
    expect(p.loaded, isFalse);
    expect(p.isEmpty, isFalse);
    expect(p.error, isA<StateError>());
  });

  test('a failed page keeps what is shown and can be retried', () async {
    var fail = true;
    final p = CursorPager<String>(
      fetch: (cursor) async {
        if (cursor == null) return const CursorPage(['a'], 'c1');
        if (fail) throw StateError('offline');
        return const CursorPage(['b'], null);
      },
      idOf: (s) => s,
    );
    await p.refresh();
    await p.loadMore();
    expect(p.items, ['a']);
    expect(p.error, isNotNull);
    expect(p.hasMore, isTrue);

    fail = false;
    await p.loadMore();
    expect(p.items, ['a', 'b']);
    expect(p.error, isNull);
  });

  test('a page that lands after a refresh is dropped', () async {
    final slow = Completer<CursorPage<String>>();
    var calls = 0;
    final p = CursorPager<String>(
      fetch: (cursor) {
        calls++;
        if (cursor == 'c1') return slow.future;
        return Future.value(
          calls == 1
              ? const CursorPage(['a'], 'c1')
              : const CursorPage(['fresh'], null),
        );
      },
      idOf: (s) => s,
    );
    await p.refresh();
    final more = p.loadMore();
    await p.refresh();
    slow.complete(const CursorPage(['stale'], null));
    await more;
    expect(p.items, ['fresh']);
  });
}
