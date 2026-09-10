import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/search/domain/entities/cross_search_scope.dart';

ProviderEntity _p(String id) => ProviderEntity(
  id: id,
  name: id,
  image: '',
  url: '',
  description: '',
  domains: const [],
);

void main() {
  final providers = [_p('a'), _p('b'), _p('c')];

  group('default scope', () {
    test('a user who never opened the picker searches every source', () {
      final scope = CrossSearchScope.fromStored(const []);
      expect(scope.isAll, isTrue);
      expect(scope.resolve(providers).length, 3);
    });

    test('an empty narrowing is all, not a search with no legs', () {
      expect(CrossSearchScope.only(const <String>[]).isAll, isTrue);
      expect(
        CrossSearchScope.only({'a'}).toggle('a').isAll,
        isTrue,
        reason: 'toggling the last source off widens back to all',
      );
    });
  });

  group('pruning', () {
    test('uninstalled ids are dropped', () {
      final scope = CrossSearchScope.only({'a', 'gone'}).pruned(providers);
      expect(scope.ids, {'a'});
    });

    test('pruning everything away widens back to all', () {
      expect(CrossSearchScope.only({'gone'}).pruned(providers).isAll, isTrue);
    });

    test(
      'an explicit set stays explicit rather than becoming capped quick search',
      () {
        final stored = CrossSearchScope.fromStored(const ['a', 'b', 'c']);
        final scope = stored.pruned(providers);
        expect(scope.isAll, isFalse);
        expect(scope.resolve([...providers, _p('d')]).length, 3);
      },
    );
  });

  group('toggling from all', () {
    test('a tap narrows to that one source rather than excluding it', () {
      final scope = const CrossSearchScope.all().toggle('b');
      expect(scope.ids, {'b'});
    });
  });

  test('round-trips through storage', () {
    final scope = CrossSearchScope.only({'a', 'c'});
    expect(CrossSearchScope.fromStored(scope.toStored()), scope);
    expect(
      CrossSearchScope.fromStored(
        const CrossSearchScope.all().toStored(),
      ).isAll,
      isTrue,
    );
  });
}
