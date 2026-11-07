/// Which verdicts are worth showing, and which ones are not about this phone.
///
/// Two witnesses report on a source and they do not have the same standing.
/// The server sweeps every extension's SITE three times a week from a
/// datacenter; this phone runs the source's own code over its own network. For
/// a Sozo cloud source those are the same question, because the catalogue
/// reaches the app through the backend either way — if the backend cannot read
/// the site, neither can the reader. For everything else they are not: a
/// CloudStream, Aniyomi, Manga, Mangayomi or Jellyfin source talks to its site
/// from the handset, over a residential address, and a datacenter's result says
/// nothing about that leg.
///
/// Measured against the live report on 2026-11-02: of 930 extension verdicts,
/// 229 said "dead", and 96 of those were a TLS handshake, a timeout or an
/// unreachable address — the three symptoms a site shows a datacenter and not a
/// phone. Those 96 sources carried a red "Down" badge that nothing had
/// established on the device they run on.
library;

import 'package:soplay/features/search/data/source_health_store.dart';
import 'package:soplay/features/sources/data/source_check_store.dart';
import 'package:soplay/features/sources/domain/source_ecosystem.dart';

/// Whether [providerId] fetches its own catalogue on this phone.
///
/// Every ecosystem but Sozo's own does: the prefixes are the plugin hosts, and
/// each resolves through its platform channel without the backend. See
/// `SourceBrowseRepository.load`, which routes by the same prefixes.
/// Takes an id or a health key, because callers have both to hand and the
/// distinction is not visible at the call site: `ProviderEntity.healthKey`
/// rewrites a CloudStream id as `csp:<internalName>`, which does not start with
/// the `cs:` prefix [SourceEcosystem] classifies by, so a key would have been
/// called a Sozo cloud source and handed the datacenter's verdict.
bool runsOnDevice(String providerIdOrKey) =>
    providerIdOrKey.startsWith('csp:') ||
    SourceEcosystem.of(providerIdOrKey) != SourceEcosystem.sozo;

/// Sweep reasons that describe the road between the prober and the site rather
/// than the site itself.
///
/// A parked domain is parked from everywhere and a domain that does not resolve
/// does not resolve from anywhere, so those stand wherever they were found.
/// A dropped connection, a refused handshake and a timeout are what an
/// anti-bot rule looks like from a datacenter address, and they are the ones a
/// phone routinely gets through.
const Set<String> vantageReasons = {
  'timeout',
  'unreachable',
  'tls',
  'slow_response',
};

/// The verdict worth putting on [providerId]'s row, or null for no badge.
///
/// [verdict] is whatever `SourceHealthStore.badgeOf` found. This is the last
/// word before it reaches a row, and it drops the one case that cannot be
/// defended: a source that runs on the device, called down because a check
/// from somewhere else could not get through to its site. Such a source is
/// shown plainly, with no claim either way, until a check from here says
/// something — which the row's long-press offers.
RemoteVerdict? shownVerdict(String providerId, RemoteVerdict? verdict) {
  if (verdict == null) return null;
  // This phone's own answer, which is the one we wanted all along.
  if (verdict.onDevice) return verdict;
  if (verdict.state != RemoteHealth.dead) return verdict;
  if (!runsOnDevice(providerId)) return verdict;
  return vantageReasons.contains(verdict.reason) ? null : verdict;
}

/// Whether [verdict] is something the reader should be shown among "problems".
///
/// Everything except a source that answered with titles and a source nobody
/// has asked yet. An empty catalogue belongs here: zero items is not health,
/// and a 200 with an empty list is the commonest shape of a blocked site —
/// kisskh answers the backend exactly that way today.
bool isProblemVerdict(SourceVerdict verdict) =>
    verdict != SourceVerdict.alive && verdict != SourceVerdict.unknown;

/// The verdict this phone found that deserves a badge of its own, or null.
///
/// Two witnesses, and only one of them has a badge. `SourceHealthStore.badgeOf`
/// can say "Down" and "Cloudflare" and nothing else, so it answers null for an
/// empty catalogue and says nothing for a source that has merely started
/// failing. Those rows survive the problems-only filter — [isProblemVerdict]
/// counts them, and should — and then sat there with no pill and no explanation
/// of what was wrong with them. kisskh is the live example: it answers the
/// backend 200 with an empty list, which is the commonest shape of a site that
/// has shut the prober out.
///
/// [shown] is the badge the row already has. When there is one it speaks for
/// the row and a second pill beside it would only disagree in public; the
/// device verdict is reached through the row's long-press either way.
SourceVerdict? deviceBadge(SourceVerdict device, RemoteVerdict? shown) {
  if (shown != null) return null;
  return switch (device) {
    SourceVerdict.empty || SourceVerdict.failing => device,
    _ => null,
  };
}

/// Rows with the down ones last, and the count of the ones hiding removes.
class DownPartition<T> {
  const DownPartition({required this.rows, required this.hidable});

  /// In order: the working ones as they came, then the down ones — minus the
  /// down ones, when hiding was asked for.
  final List<T> rows;

  /// How many rows hiding takes away. The same number whether hiding is on or
  /// off, so the switch can promise it before it is flipped.
  final int hidable;
}

/// Sinks the down rows of [rows], or leaves them out when [hide].
///
/// The hub had the count and the hiding in two places: a tally over every row
/// of the tab, and a filter over the rows left after the scope and language
/// menus. "Hide down sources · 7" then took four rows away, because three of
/// the seven were not on screen to begin with and one was the source in use,
/// which is never hidden. One function now answers both questions from the
/// same list, so the number is the number.
///
/// [keep] names rows that are never hidden — the source in use has to stay
/// findable, even when it is the broken one.
DownPartition<T> partitionDown<T>(
  List<T> rows, {
  required bool Function(T) isDown,
  bool Function(T)? keep,
  bool hide = false,
}) {
  final up = <T>[];
  final down = <T>[];
  var hidable = 0;
  for (final row in rows) {
    if (!isDown(row)) {
      up.add(row);
      continue;
    }
    down.add(row);
    if (!(keep?.call(row) ?? false)) hidable++;
  }
  if (down.isEmpty) return DownPartition(rows: rows, hidable: 0);
  return DownPartition(
    rows: [
      ...up,
      for (final row in down)
        if (!hide || (keep?.call(row) ?? false)) row,
    ],
    hidable: hidable,
  );
}
