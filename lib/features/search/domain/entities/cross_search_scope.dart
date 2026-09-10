import 'package:soplay/features/profile/domain/entities/provider_entity.dart';

/// Which sources an all-source search covers.
///
/// Deliberately *not* a plain `Set<String>`: "every source" and "these twelve
/// sources, which happen to be all of them today" behave differently the moment
/// the installed list changes. A frozen id set silently stops covering a source
/// the user installs later, and an empty set is indistinguishable from "the user
/// has not chosen yet" — which is how the page ended up searching one provider
/// and reporting "0 of 1".
class CrossSearchScope {
  const CrossSearchScope.all() : ids = null;

  const CrossSearchScope._only(this.ids);

  /// Narrows to [ids]; an empty selection is not a scope, it is [all].
  factory CrossSearchScope.only(Iterable<String> ids) {
    final set = ids.toSet();
    return set.isEmpty
        ? const CrossSearchScope.all()
        : CrossSearchScope._only(set);
  }

  /// Null means "everything usable", which is the default.
  final Set<String>? ids;

  bool get isAll => ids == null;

  /// The stored form: an empty list means [all], so a user who never opened the
  /// picker searches everything rather than inheriting some other screen's
  /// notion of a "current" provider.
  factory CrossSearchScope.fromStored(List<String> stored) =>
      CrossSearchScope.only(stored);

  List<String> toStored() => ids?.toList() ?? const [];

  bool includes(String id) => ids == null || ids!.contains(id);

  List<ProviderEntity> resolve(List<ProviderEntity> providers) => ids == null
      ? providers
      : providers.where((p) => ids!.contains(p.id)).toList();

  int selectedCount(List<ProviderEntity> providers) =>
      resolve(providers).length;

  /// Drops ids that are no longer installed. Narrowing to nothing widens back
  /// to [all] rather than leaving a search with no legs at all. An explicit set
  /// stays explicit even if it names every installed source: changing it into
  /// quick search on the next launch would silently apply the 60-source cap.
  CrossSearchScope pruned(List<ProviderEntity> providers) {
    if (ids == null) return this;
    final installed = providers.map((p) => p.id).toSet();
    final kept = ids!.where(installed.contains).toSet();
    return CrossSearchScope.only(kept);
  }

  /// One tap on a source chip.
  ///
  /// From [all] a tap means "just this one" — the chips read as unselected
  /// there, so the alternative ("everything except this one") would be the
  /// opposite of what the control looks like it does.
  CrossSearchScope toggle(String id) {
    if (ids == null) return CrossSearchScope.only({id});
    final next = {...ids!};
    if (!next.remove(id)) next.add(id);
    return CrossSearchScope.only(next);
  }

  @override
  bool operator ==(Object other) =>
      other is CrossSearchScope &&
      (ids == null) == (other.ids == null) &&
      (ids == null ||
          (ids!.length == other.ids!.length && ids!.containsAll(other.ids!)));

  @override
  int get hashCode => ids == null ? 0 : Object.hashAllUnordered(ids!);
}
