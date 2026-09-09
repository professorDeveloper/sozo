import 'package:soplay/features/detail/data/title_prefs_store.dart';
import 'package:soplay/features/detail/domain/entities/video_source_entity.dart';

/// Which mirror to play, and which one to try after that.
///
/// A resolve hands back several mirrors of the same episode. Deciding between
/// them was spread across four places that each answered it differently: a
/// movie consulted the remembered quality, an episode took `sources[0]`
/// outright, a watch-party guest took `sources[0]` too, and the retry path
/// took `_currentSourceIndex + 1` exactly once before giving up. So the same
/// title played at a different quality depending on how you opened it, and a
/// list of five mirrors was never walked past the second.
///
/// This is that decision, alone, as data in and an index out. No Flutter, no
/// getIt, no I/O, no clock — there is a test that keeps it that way.
///
/// ## Why untried mirrors are tracked by url, not index
///
/// The candidate list is REPLACED on every re-resolve (`_loadEpisode` builds a
/// new one), so an index means nothing across that boundary — index 2 of the
/// old list is a different mirror in the new one. The retry path re-resolves,
/// which is exactly when the old bookkeeping was wiped and the walk restarted
/// at the top. Urls survive it.
class SourceLadder {
  const SourceLadder({
    required this.sources,
    required this.hasDirective,
    this.rememberedQuality,
    this.avoidCodec,
    this.triedUrls = const <String>{},
  });

  final List<VideoSourceEntity> sources;

  /// Whether the resolve carried an extractor directive
  /// (`MediaResolveEntity.extractor`), i.e. whether an embed page will be
  /// sniffed for its real stream before playback.
  final bool hasDirective;

  /// The quality label this title was last watched at, if any. Matched on the
  /// label rather than the index, because the label is what the viewer chose
  /// and the index is an accident of whatever the resolve returned this time.
  final String? rememberedQuality;

  /// Set after a decoder failure, so sibling mirrors in the same codec go to
  /// the back of the queue. Demoted, never dropped — an h265-only title must
  /// still play its h265 rather than report that it has no sources.
  final String? avoidCodec;

  /// Mirrors already attempted this session, by `videoUrl`.
  final Set<String> triedUrls;

  /// Whether this candidate is worth handing to the player at all.
  ///
  /// Two ways it is not. A source the backend already probed and marked
  /// unreachable is a wasted attempt with a spinner in front of it. And a
  /// `type: 'iframe'` entry is not a stream — it is an embed PAGE. Some
  /// providers push one first for every server, so `sources[0]` was routinely
  /// an HTML document handed to a video decoder. That only becomes playable
  /// once a directive says a WebView will sniff the real stream out of it.
  static bool isPlayable(
    VideoSourceEntity s, {
    required bool hasDirective,
  }) {
    if (!s.accessible) return false;
    if (s.videoUrl.isEmpty) return false;
    if (s.type == 'iframe' && !hasDirective) return false;
    return true;
  }

  /// Every candidate still worth trying, best first, as indices into [sources].
  ///
  /// Precedence, in order:
  ///   1. the remembered quality label — an explicit past choice outranks
  ///      everything below it;
  ///   2. the source's own default;
  ///   3. the order the backend returned, which is already ranked.
  /// A codec being avoided sinks below all three without leaving the list.
  List<int> ordered() {
    final candidates = <int>[];
    for (var i = 0; i < sources.length; i++) {
      final s = sources[i];
      if (!isPlayable(s, hasDirective: hasDirective)) continue;
      if (triedUrls.contains(s.videoUrl)) continue;
      candidates.add(i);
    }

    final avoid = avoidCodec?.toLowerCase();
    int rank(int i) {
      final s = sources[i];
      if (avoid != null && s.codec?.toLowerCase() == avoid) return 3;
      if (rememberedQuality != null && s.quality == rememberedQuality) return 0;
      if (s.isDefault) return 1;
      return 2;
    }

    // Stable: equal ranks keep the backend's order, which is the third rule.
    candidates.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.compareTo(b);
    });
    return candidates;
  }

  /// The next mirror to try, or null when every one has been tried.
  ///
  /// Null is the ONLY thing that should reach an error screen. Before this,
  /// one failed attempt ended the walk with untried mirrors still in the list.
  int? next() {
    final list = ordered();
    return list.isEmpty ? null : list.first;
  }

  /// The mirror to START on, which is never "none" when sources exist.
  ///
  /// [next] is the walk: strict, and null means the ladder is exhausted, which
  /// is what an error screen waits for. The first pick is a different question.
  /// The picker this replaced ended in `return 0` — play SOMETHING — and that
  /// last resort matters: with no index the player falls back to the resolve's
  /// top-level url, `_currentQuality` stays null, and a null quality means a
  /// null server, which made the Quality panel list every mirror across every
  /// host. Pressing Quality then showed servers.
  ///
  /// So: the ranked choice when there is one, else the first source, else null
  /// only when there genuinely are none.
  int? initialPick() => next() ?? (sources.isEmpty ? null : 0);

  /// The remembered quality for a title, or null. Here rather than at the call
  /// sites so the two that consult it and the two that never did all read one
  /// implementation.
  static String? rememberedQualityFor(
    TitlePrefsStore prefs, {
    required String provider,
    required String contentUrl,
  }) {
    final value = prefs.qualityFor(provider, contentUrl);
    return (value != null && value.isNotEmpty) ? value : null;
  }
}
