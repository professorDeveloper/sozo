import 'package:flutter/foundation.dart';

import 'package:soplay/features/social/domain/social_models.dart';

typedef PageFetcher<T> = Future<CursorPage<T>> Function(String? cursor);

/// One cursor-paged list: first load, pull to refresh, load more.
///
/// Rows are de-duplicated by [idOf] because the feed moves an updated entry
/// to the top, so the same entry can come back on a later page.
class CursorPager<T> extends ChangeNotifier {
  CursorPager({required this.fetch, required this.idOf});

  final PageFetcher<T> fetch;
  final String Function(T) idOf;

  List<T> _items = const [];
  String? _cursor;
  bool _loaded = false;
  bool _loading = false;
  bool _loadingMore = false;
  Object? _error;
  int _generation = 0;
  bool _disposed = false;

  List<T> get items => _items;
  bool get loaded => _loaded;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _cursor != null;
  Object? get error => _error;
  bool get isEmpty => _loaded && _items.isEmpty;

  /// Replaces the list with a fresh first page. Rows already on screen stay
  /// until the new page arrives, so a refresh never blanks the list.
  Future<void> refresh() async {
    final gen = ++_generation;
    _loading = true;
    _loadingMore = false;
    _notify();
    try {
      final page = await fetch(null);
      if (gen != _generation) return;
      _items = _dedupe(const [], page.items);
      _cursor = page.nextCursor;
      _error = null;
      _loaded = true;
    } catch (e) {
      if (gen != _generation) return;
      _error = e;
    } finally {
      if (gen == _generation) {
        _loading = false;
        _notify();
      }
    }
  }

  Future<void> loadMore() async {
    final cursor = _cursor;
    if (cursor == null || _loading || _loadingMore) return;
    final gen = _generation;
    _loadingMore = true;
    _notify();
    try {
      final page = await fetch(cursor);
      if (gen != _generation) return;
      _items = _dedupe(_items, page.items);
      // A page made only of repeats with the same cursor would loop forever.
      _cursor = page.nextCursor == cursor ? null : page.nextCursor;
      _error = null;
    } catch (e) {
      if (gen != _generation) return;
      _error = e;
    } finally {
      if (gen == _generation) {
        _loadingMore = false;
        _notify();
      }
    }
  }

  void removeWhere(bool Function(T) test) {
    final next = _items.where((e) => !test(e)).toList();
    if (next.length == _items.length) return;
    _items = next;
    _notify();
  }

  List<T> _dedupe(List<T> head, List<T> tail) {
    final seen = <String>{for (final e in head) idOf(e)};
    return [
      ...head,
      for (final e in tail)
        if (seen.add(idOf(e))) e,
    ];
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
