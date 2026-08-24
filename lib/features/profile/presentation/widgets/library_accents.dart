import 'dart:async';

import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_accent.dart';
import 'package:soplay/features/history/data/history_service.dart';

/// Accents pulled out of the posters of what the user actually watches.
///
/// The idea is that the best accent for a person's app is usually already on
/// their home screen — the colour of the show they are three episodes into. So
/// instead of only offering twelve colours somebody else chose, Appearance
/// offers the ones their own library is made of.
///
/// Every extracted colour still goes through [AppAccent.custom], so a poster's
/// pale cream or near-black is pulled into the legible band like any other
/// custom pick — the swatch row can never produce an unreadable theme.
class LibraryAccents {
  LibraryAccents._();

  /// How many recent titles to read. Each one is a network image decode, so
  /// this is deliberately small — the row is a nice-to-have on a settings page,
  /// not something worth spending a user's data on.
  static const int _maxPosters = 5;

  /// How many swatches the row shows.
  static const int _maxSwatches = 6;

  /// Beyond this the extraction is abandoned. A settings page that hangs
  /// waiting for a poster is worse than one that quietly has no suggestions.
  static const Duration _budget = Duration(seconds: 6);

  /// Resolved once per app run. The posters do not change while the user is on
  /// the Appearance page, and this page rebuilds on every colour tap — without
  /// the cache, every tap would re-decode five images.
  static Future<List<AppAccent>>? _cached;

  static Future<List<AppAccent>> load() => _cached ??= _extract();

  /// Drops the cache, so a later visit re-reads a library that has since
  /// changed. Called when history is cleared.
  static void invalidate() => _cached = null;

  static Future<List<AppAccent>> _extract() async {
    try {
      return await _run().timeout(_budget);
    } catch (_) {
      // Offline, an expired poster URL, a decode failure — all of them mean
      // the same thing here: no suggestions, and no error to show for it.
      return const [];
    }
  }

  static Future<List<AppAccent>> _run() async {
    final history = getIt<HistoryService>().getAll();
    final urls = <String>[];
    for (final item in history) {
      final thumb = item.thumbnail;
      if (thumb == null || thumb.isEmpty) continue;
      if (!thumb.startsWith('http')) continue;
      if (urls.contains(thumb)) continue;
      urls.add(thumb);
      if (urls.length >= _maxPosters) break;
    }
    if (urls.isEmpty) return const [];

    // In parallel: five sequential decodes would routinely exceed the budget,
    // and a failure on one poster must not cost the other four.
    final palettes = await Future.wait(
      urls.map(_paletteOf),
      eagerError: false,
    );

    final picked = <AppAccent>[];
    final takenHues = <int>{};
    for (final palette in palettes) {
      if (palette == null) continue;
      for (final candidate in _candidatesOf(palette)) {
        final accent = AppAccent.custom(candidate);
        // Bucket by 30° of hue so five posters from the same franchise cannot
        // fill the row with five near-identical blues.
        final bucket = (HSLColor.fromColor(accent.base).hue ~/ 30).clamp(0, 11);
        if (!takenHues.add(bucket)) continue;
        picked.add(accent);
        if (picked.length >= _maxSwatches) return picked;
        break; // one colour per poster, so the row reads as one per title
      }
    }
    return picked;
  }

  static Future<PaletteGenerator?> _paletteOf(String url) async {
    try {
      return await PaletteGenerator.fromImageProvider(
        NetworkImage(url),
        // Downscaled hard: the palette of a poster survives a 64px thumbnail,
        // and decoding full-size art for a settings row would not be a fair
        // trade for the user's memory.
        size: const Size(64, 64),
        maximumColorCount: 8,
      );
    } catch (_) {
      return null;
    }
  }

  /// Ordered by how much of the poster's character each one carries.
  static Iterable<Color> _candidatesOf(PaletteGenerator palette) sync* {
    for (final swatch in [
      palette.vibrantColor,
      palette.darkVibrantColor,
      palette.lightVibrantColor,
      palette.dominantColor,
      palette.mutedColor,
    ]) {
      if (swatch != null) yield swatch.color;
    }
  }
}
