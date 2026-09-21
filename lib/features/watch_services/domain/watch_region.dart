import 'package:soplay/features/watch_services/domain/entities/watch_region_entity.dart';

/// The flag for an ISO country code, built from regional-indicator letters.
///
/// A picture rather than two letters, with no asset to ship and none to fail to
/// load. Returns '' for anything that is not two A-Z letters, and callers
/// suppress it on Windows, where the pair renders as two letterboxed letters
/// rather than a flag.
String regionFlag(String code) {
  final c = code.trim().toUpperCase();
  if (c.length != 2) return '';
  final a = c.codeUnitAt(0);
  final b = c.codeUnitAt(1);
  if (a < 0x41 || a > 0x5A || b < 0x41 || b > 0x5A) return '';
  const base = 0x1F1E6 - 0x41;
  return String.fromCharCodes([base + a, base + b]);
}

/// The region to browse, given what is stored and what TMDB actually lists.
///
/// [stored] wins whenever TMDB still lists it. Otherwise the device's country,
/// which is why the stored value starts empty rather than at a default — a
/// phone carried across a border should follow, not stay frozen on wherever it
/// first launched. 'US' only when neither is available, because it is the
/// region TMDB has the most for and an empty shelf helps nobody.
///
/// A [stored] code TMDB has dropped falls back rather than sticking: a screen
/// of nothing under a flag is worse than a screen of somewhere else's films.
String resolveRegion(
  String stored,
  List<WatchRegionEntity> known, {
  String? deviceCountry,
}) {
  bool lists(String code) => known.isEmpty || known.any((r) => r.code == code);

  final chosen = stored.trim().toUpperCase();
  if (chosen.isNotEmpty && lists(chosen)) return chosen;

  final device = (deviceCountry ?? '').trim().toUpperCase();
  if (device.length == 2 && lists(device)) return device;

  return 'US';
}
