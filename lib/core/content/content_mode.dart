import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/extensions/provider_media_kind.dart';
import 'package:soplay/features/extensions/data/mangayomi_repo_store.dart';
import 'package:soplay/features/extensions/domain/entities/mangayomi_source.dart';

/// What kind of thing the app is showing right now.
///
/// ## Why this exists
///
/// Sources of three quite different kinds share one list: an anime provider, a
/// manga provider and a novel provider sit next to each other with nothing but
/// their name to tell them apart. Somebody who came to read has to know which
/// of thirty entries is a reader, and the reported version of that was "every
/// time I want to change extension source I have to go to settings".
///
/// A mode is the answer: it narrows every source list to the kind you are
/// actually in, so switching becomes a choice between four things instead of
/// thirty.
///
/// ## Why it is derived and not stored per source
///
/// [ProviderMediaKind] already answers "reader or player" and is the single
/// place that does. This splits the reader half in two, because a manga
/// provider and a novel provider are as different to a reader as an anime
/// provider is — and Mangayomi already labels which is which. Nothing here
/// re-decides what [ProviderMediaKind] already decided.
enum ContentMode {
  /// Anime, films and series — everything that opens the player.
  video('video', 'mode.video'),

  /// Manga, manhwa and webtoons.
  manga('manga', 'mode.manga'),

  /// Light novels and text.
  novel('novel', 'mode.novel');

  const ContentMode(this.id, this.labelKey);

  /// Persisted in Hive. Never rename one.
  final String id;
  final String labelKey;

  static ContentMode fromId(String? id) {
    for (final m in ContentMode.values) {
      if (m.id == id) return m;
    }
    // Video is both the safe answer and what every install had before modes
    // existed: the great majority of sources are video, and a wrong guess here
    // shows somebody a shorter list, never an empty app.
    return ContentMode.video;
  }

  /// Whether a provider belongs in this mode.
  bool accepts(String providerId) => providerId.contentMode == this;
}

extension ContentModeX on String {
  /// The mode this provider id belongs to.
  ///
  /// Built on [mediaKind] rather than beside it, so there is still exactly one
  /// place that decides reader-versus-player and this only refines the reader
  /// half. A Mangayomi source that declares itself a novel is a novel; anything
  /// else that reads is manga, because the manga index dwarfs the novel one and
  /// an unlabelled reader is far more likely to be one.
  ContentMode get contentMode {
    if (mediaKind == ProviderMediaKind.video) return ContentMode.video;
    if (startsWith('my:')) {
      final source = _source(this);
      if (source?.itemType == MangayomiItemType.novel) return ContentMode.novel;
    }
    return ContentMode.manga;
  }
}

MangayomiSource? _source(String providerId) {
  try {
    return getIt<MangayomiRepoStore>().sourceById(providerId);
  } catch (_) {
    // DI not ready — unit tests and early startup.
    return null;
  }
}
