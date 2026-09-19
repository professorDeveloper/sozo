import 'package:soplay/core/di/injection.dart';
import 'package:soplay/features/extensions/data/mangayomi_repo_store.dart';
import 'package:soplay/features/extensions/domain/entities/mangayomi_source.dart';
import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/content/content_mode.dart';

/// Whether a provider's "episodes" are pages to read or a stream to play.
///
/// This is the single place that answers "reader or player?". It used to be a
/// bare `provider.startsWith('mn:')` inline in the episodes screen, which was
/// correct while `mn:` was the only reading source. It stopped being correct the
/// moment Mangayomi arrived: a `my:` provider can be manga, a novel **or** an
/// anime — the same prefix covers all three — so the prefix alone cannot decide.
/// Sending a MangaDex chapter to the video player produced a permanently
/// spinning player with no stream to find.
enum ProviderMediaKind {
  /// Opens `/player` — anime and video sources.
  video,

  /// Opens `/reader` — manga, manhwa, webtoon and novel sources.
  reader,
}

extension ProviderMediaKindX on String {
  /// Media kind for this provider id.
  ///
  /// Unknown providers default to [ProviderMediaKind.video]: every server and
  /// CloudStream provider is a video source, so that is both the safe answer
  /// and the historical behaviour.
  ProviderMediaKind get mediaKind {
    if (startsWith('mn:')) return ProviderMediaKind.reader;
    if (Catalogue.isId(this)) {
      return Catalogue.fromId(this)?.mode == ContentMode.video
          ? ProviderMediaKind.video
          : ProviderMediaKind.reader;
    }
    if (startsWith('my:')) {
      // Resolve per source — a Mangayomi repo mixes manga, anime and novels.
      // Falls back to reader because the manga index is by far the largest and
      // the anime ones are a small minority; a wrong guess here is only ever
      // hit for a source that is not installed.
      final source = _mangayomiSource(this);
      return switch (source?.itemType) {
        MangayomiItemType.anime => ProviderMediaKind.video,
        _ => ProviderMediaKind.reader,
      };
    }
    return ProviderMediaKind.video;
  }

  bool get opensReader => mediaKind == ProviderMediaKind.reader;
}

MangayomiSource? _mangayomiSource(String providerId) {
  try {
    return getIt<MangayomiRepoStore>().sourceById(providerId);
  } catch (_) {
    // DI not ready (unit tests, early startup) — treat as unknown.
    return null;
  }
}
