import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';
import 'package:soplay/features/detail/domain/entities/ani_info.dart';
import 'package:soplay/features/detail/domain/entities/cast_entity.dart';
import 'package:soplay/features/detail/domain/entities/detail_entity.dart';
import 'package:soplay/features/detail/domain/entities/related_entity.dart';
import 'package:soplay/features/detail/domain/services/catalogue_resolver.dart';

/// A detail page built from AniList's record of a title, playing from
/// whichever source was found for it.
///
/// The words, the poster, the score and the cast are AniList's; the provider
/// and the content url are the source's, so episodes and playback go where
/// they must. When no source was found the provider stays the catalogue's own
/// id, and the page offers to look rather than a Play that cannot.
DetailEntity detailFromAnilist(AnilistMediaDetail d, {CatalogueLink? via}) {
  final m = d.media;
  final title = m.englishTitle ?? m.romajiTitle ?? m.nativeTitle ?? '';
  return DetailEntity(
    provider: via?.providerId ?? Catalogue.anilist.id,
    contentId: '${m.id}',
    contentUrl:
        via?.contentUrl ?? (m.siteUrl ?? 'https://anilist.co/anime/${m.id}'),
    title: title,
    description: _plain(m.description ?? ''),
    thumbnail: m.coverImage,
    year: m.seasonYear,
    duration: d.durationMinutes != null ? '${d.durationMinutes} min' : null,
    country: _country(d.countryOfOrigin),
    director: null,
    genres: d.genres,
    // Characters, with the character's face — that is who the viewer
    // recognises. The voice actor rides along in the name so the row reads
    // "Frieren · Tanezaki Atsumi".
    cast: [
      for (final c in d.characters)
        if (c.name.isNotEmpty)
          CastEntity(
            id: c.name,
            name: c.voiceActor != null ? '${c.name} · ${c.voiceActor}' : c.name,
            image: c.image ?? '',
          ),
    ],
    likes: 0,
    dislikes: 0,
    isSerial: m.format != 'MOVIE',
    isFavorited: null,
    screenshots: const [],
    // AniList's recommendations, as catalogue cards: opening one resolves a
    // source for it the same way this page was resolved.
    related: [
      for (final r in d.recommendations)
        RelatedEntity(
          provider: Catalogue.anilist.id,
          externalId: '${r.id}',
          title: r.englishTitle ?? r.romajiTitle ?? r.nativeTitle ?? '',
          description: '',
          slug: '${r.id}',
          contentUrl: r.siteUrl ?? 'https://anilist.co/anime/${r.id}',
          thumbnail: r.coverImage,
          year: r.seasonYear,
          rating: r.averageScore != null ? (r.averageScore! / 10).round() : 0,
          qualities: const [],
          category: 'anime',
        ),
    ],
    trailerYoutubeId: d.trailerYoutubeId,
    ani: AniInfo(
      anilistId: m.id,
      malId: m.idMal,
      score: d.meanScore != null ? d.meanScore! / 10 : null,
      rankText: d.rankText,
      studio: d.studio,
      source: d.source,
      format: m.format,
      status: m.status,
      episodes: m.episodes,
      tags: d.tags,
      nextEpisode: m.nextAiring?.episode,
      nextAiringAt: m.nextAiring?.airsAt,
    ),
  );
}

/// The AniList id in a catalogue content url, or in a card's id.
int? anilistIdFrom(String contentUrl, {String? externalId}) {
  final fromId = int.tryParse(externalId ?? '');
  if (fromId != null) return fromId;
  final m = RegExp(r'anilist\.co/anime/(\d+)').firstMatch(contentUrl);
  return m == null ? null : int.tryParse(m.group(1)!);
}

/// AniList descriptions arrive with `<br>` and `<i>` in them even when asked
/// for plain text.
String _plain(String html) => html
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&quot;', '"')
    .replaceAll('&#039;', "'")
    .replaceAll('&amp;', '&')
    .trim();

String? _country(String? code) => switch (code) {
  'JP' => 'Japan',
  'KR' => 'South Korea',
  'CN' => 'China',
  'TW' => 'Taiwan',
  'US' => 'United States of America',
  null => null,
  _ => code,
};
