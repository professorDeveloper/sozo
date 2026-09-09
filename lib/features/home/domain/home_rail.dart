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

  /// The genre chips.
  genres('genres', 'home_rails.genres', Icons.category_outlined),

  /// Live TV.
  liveTv('live_tv', 'home_rails.live_tv', Icons.live_tv_outlined),

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
    genres,
    liveTv,
    catalogue,
  ];
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
///    than being invisible until somebody opens the customizer;
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
    if (!out.contains(rail)) out.add(rail);
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
