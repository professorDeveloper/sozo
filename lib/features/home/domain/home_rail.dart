import 'package:flutter/material.dart';

/// A movable band on the home screen.
///
/// ## Why only these five
///
/// Home is four fixed bands plus whatever the current provider serves. The
/// fixed ones have a stable identity, so they can be reordered and remembered.
/// The provider's own sections cannot: their names come from whichever source
/// is selected and change with it and with the language, so there is no key to
/// remember a choice against. They move together as [catalogue] — one band that
/// happens to contain several rails.
///
/// Pretending otherwise would give somebody a list of section names that
/// silently becomes a different list the moment they change source, with their
/// ordering applied to whatever now sits in those positions.
enum HomeRail {
  /// The big carousel at the top.
  hero('hero', 'home_rails.hero', Icons.view_carousel_outlined),

  /// Continue Watching.
  resume('resume', 'home_rails.resume', Icons.play_circle_outline),

  /// New episodes and chapters of followed titles. Draws nothing until there
  /// is something unseen.
  newReleases(
    'new_releases',
    'home_rails.new_releases',
    Icons.new_releases_outlined,
  ),

  /// The genre chips.
  genres('genres', 'home_rails.genres', Icons.category_outlined),

  /// Live TV.
  liveTv('live_tv', 'home_rails.live_tv', Icons.live_tv_outlined),

  /// What the streaming services carry, in the viewer's country.
  ///
  /// Enabled by default on movie home; the customizer can hide it.
  watchServices(
    'watch_services',
    'home_rails.watch_services',
    Icons.subscriptions_outlined,
  ),

  /// Everything the current source serves, in the order it serves it.
  catalogue('catalogue', 'home_rails.catalogue', Icons.grid_view_outlined);

  const HomeRail(this.id, this.labelKey, this.icon);

  /// Persisted. Never rename one.
  final String id;
  final String labelKey;
  final IconData icon;

  static HomeRail? fromId(String? id) {
    for (final r in HomeRail.values) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// The order home has always had, and what an install with no stored choice
  /// gets.
  static const List<HomeRail> defaults = [
    hero,
    resume,
    newReleases,
    genres,
    liveTv,
    watchServices,
    catalogue,
  ];

  /// Bands that are in [defaults] — so they have a place in the order and a
  /// row in the customizer — but are switched OFF until asked for.
  ///
  /// The distinction matters on upgrade as much as on a fresh install: a band
  /// added in a new version arrives in everybody's order, and without this
  /// every existing install would find something new on Home that nobody put
  /// there.
  static const Set<String> optIn = {};

  bool get isOptIn => optIn.contains(id);

  /// Where a band lands in an order stored before it existed, when the end
  /// of the list would bury it. New episodes belong beside Continue
  /// Watching, not under an endless catalogue.
  static const Map<HomeRail, HomeRail> arrivesAfter = {newReleases: resume};
}

/// Repairs a stored order into one that can actually be rendered.
///
/// Stored lists outlive the code that wrote them: a rail can be added in a
/// later version and a stored list will not have it, or removed and a stored
/// list will still name it. Rather than validate at every read site, every read
/// goes through here.
///
/// Rules, in order:
///  * unknown ids are dropped — they name a rail this build does not have;
///  * duplicates are dropped — a rail can only be in one place;
///  * rails missing from the list are appended, so a new one appears rather
///    than being invisible until somebody opens the customizer — or, for one
///    named in [HomeRail.arrivesAfter], placed after its anchor;
///  * an empty result falls back to the defaults, because a home screen with no
///    bands is not a preference, it is a broken screen.
List<HomeRail> sanitizeRailOrder(List<String> stored) {
  final out = <HomeRail>[];
  for (final id in stored) {
    final rail = HomeRail.fromId(id);
    if (rail != null && !out.contains(rail)) out.add(rail);
  }
  if (out.isEmpty) return List.of(HomeRail.defaults);
  for (final rail in HomeRail.defaults) {
    if (out.contains(rail)) continue;
    final anchor = HomeRail.arrivesAfter[rail];
    if (anchor != null && out.contains(anchor)) {
      out.insert(out.indexOf(anchor) + 1, rail);
    } else {
      out.add(rail);
    }
  }
  return out;
}

/// The rails that are switched on, in their stored order.
///
/// [hidden] names what to leave out. At least one rail always survives: hiding
/// everything leaves a blank screen with no way back except the customizer,
/// which somebody who just hid everything has no reason to look for.
List<HomeRail> visibleRails(List<HomeRail> order, Set<String> hidden) {
  final shown = [
    for (final r in order)
      if (!hidden.contains(r.id)) r,
  ];
  return shown.isEmpty ? [HomeRail.catalogue] : shown;
}

/// [order] with [id] moved to sit directly after [after].
///
/// So that a band somebody accepts appears where they were asked about it.
/// The offer is a card among the rails — after Genres — and taking it up used
/// to drop the band wherever [HomeRail.defaults] happened to put it, which on
/// a default install is three rails further down. Tapping "add" and watching
/// something appear somewhere else reads as having pressed the wrong thing.
///
/// Ids rather than rails, because that is what is stored, and unknown ids are
/// left where they are: a stored order can name a band this version has
/// dropped, and re-ordering around it must not quietly delete it.
List<String> placeRailAfter(List<String> order, String id, String after) {
  if (id == after) return order;
  final out = [...order];
  if (!out.contains(id) || !out.contains(after)) return out;
  out.remove(id);
  out.insert(out.indexOf(after) + 1, id);
  return out;
}
