import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/features/detail/data/models/detail_model.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';
import 'package:soplay/features/detail/domain/entities/record_info.dart';
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
  // Which shelf the page belongs to: a manga id is a manga page whichever
  // catalogue it was opened from, and a light novel is the novel shelf.
  final catalogue = !m.isManga
      ? Catalogue.anilist
      : (m.format == 'NOVEL' ? Catalogue.anilistNovel : Catalogue.anilistManga);
  final path = m.isManga ? 'manga' : 'anime';
  return DetailEntity(
    provider: via?.providerId ?? catalogue.id,
    contentId: '${m.id}',
    contentUrl:
        via?.contentUrl ?? (m.siteUrl ?? 'https://anilist.co/$path/${m.id}'),
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
    isSerial: m.isManga || m.format != 'MOVIE',
    isFavorited: null,
    screenshots: const [],
    // AniList's recommendations, as catalogue cards: opening one resolves a
    // source for it the same way this page was resolved.
    related: [
      for (final r in d.recommendations)
        RelatedEntity(
          provider: catalogue.id,
          externalId: '${r.id}',
          title: r.englishTitle ?? r.romajiTitle ?? r.nativeTitle ?? '',
          description: '',
          slug: '${r.id}',
          contentUrl: r.siteUrl ?? 'https://anilist.co/$path/${r.id}',
          thumbnail: r.coverImage,
          year: r.seasonYear,
          rating: r.averageScore != null ? (r.averageScore! / 10).round() : 0,
          qualities: const [],
          category: catalogue.mode == ContentMode.video ? 'anime' : 'manga',
        ),
    ],
    trailerYoutubeId: d.trailerYoutubeId,
    record: RecordInfo(
      anilistId: m.id,
      malId: m.idMal,
      isManga: m.isManga,
      score: d.meanScore != null ? d.meanScore! / 10 : null,
      nextEpisode: m.nextAiring?.episode,
      nextAiringAt: m.nextAiring?.airsAt,
      tags: d.tags,
      facts: [
        if (d.studio != null) RecordFact('detail.about_studio', d.studio!),
        if (d.source != null)
          RecordFact('detail.about_source', _word(d.source!)),
        if (m.episodes != null)
          RecordFact('detail.about_episodes', '${m.episodes}'),
        if (m.chapters != null)
          RecordFact('detail.about_chapters', '${m.chapters}'),
        if (m.volumes != null)
          RecordFact('detail.about_volumes', '${m.volumes}'),
        if (d.rankText != null) RecordFact('detail.about_rank', d.rankText!),
        if (m.status != null)
          RecordFact('detail.about_status', _word(m.status!)),
        if (m.format != null)
          RecordFact('detail.about_format', _word(m.format!)),
      ],
    ),
  );
}

/// The AniList id in a catalogue content url, or in a card's id.
int? anilistIdFrom(String contentUrl, {String? externalId}) {
  final fromId = int.tryParse(externalId ?? '');
  if (fromId != null) return fromId;
  final m = RegExp(r'anilist\.co/(?:anime|manga)/(\d+)').firstMatch(contentUrl);
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

/// LIGHT_NOVEL → Light novel; RELEASING → Releasing; TV_SHORT → TV short.
String _word(String raw) => [
  for (final (i, p) in raw.split('_').indexed)
    if (p.isEmpty || _initialisms.contains(p))
      p
    else if (i == 0)
      p[0] + p.substring(1).toLowerCase()
    else
      p.toLowerCase(),
].join(' ');

const _initialisms = {'TV', 'OVA', 'ONA'};

String? _country(String? code) => switch (code) {
  'JP' => 'Japan',
  'KR' => 'South Korea',
  'CN' => 'China',
  'TW' => 'Taiwan',
  'US' => 'United States of America',
  null => null,
  _ => code,
};

/// A detail page built from TMDB's record of a title, playing from whichever
/// source was found for it. The record arrives in the provider detail's own
/// shape, so the model parses it; only the provider, the url and the About
/// facts are this function's work.
DetailEntity detailFromTmdb(Map<String, dynamic> json, {CatalogueLink? via}) {
  final base = DetailModel.fromJson(json);
  final extra = json['extra'];
  final about = extra is Map ? extra['about'] : null;
  String? str(Object? v) => v == null ? null : v.toString();
  int? num_(Object? v) => v is num ? v.toInt() : int.tryParse('$v');
  final vote = extra is Map ? extra['voteAverage'] : null;
  final status = extra is Map ? str(extra['status']) : null;
  final tagline = extra is Map ? str(extra['tagline']) : null;

  DateTime? nextAt;
  int? nextEp;
  if (about is Map && about['nextEpisode'] is Map) {
    final n = about['nextEpisode'] as Map;
    nextEp = num_(n['number']);
    nextAt = DateTime.tryParse('${n['airDate']}');
  }

  return DetailEntity(
    provider: via?.providerId ?? Catalogue.tmdb.id,
    contentId: base.contentId,
    contentUrl: via?.contentUrl ?? base.contentUrl,
    title: base.title,
    description: [
      if (tagline != null && tagline.isNotEmpty) tagline,
      base.description,
    ].where((t) => t.trim().isNotEmpty).join('\n\n'),
    thumbnail: base.thumbnail,
    year: base.year,
    duration: base.duration,
    country: base.country,
    director: base.director,
    genres: base.genres,
    cast: base.cast,
    likes: 0,
    dislikes: 0,
    isSerial: base.isSerial,
    isFavorited: null,
    screenshots: base.screenshots,
    // Similar titles, re-labelled as catalogue cards so opening one resolves
    // a source the same way this page was resolved.
    related: [
      for (final r in base.related)
        RelatedEntity(
          provider: Catalogue.tmdb.id,
          externalId: r.externalId,
          title: r.title,
          description: r.description,
          slug: r.slug,
          contentUrl: r.contentUrl,
          thumbnail: r.thumbnail,
          year: r.year,
          rating: r.rating,
          qualities: r.qualities,
          category: r.category,
        ),
    ],
    trailerYoutubeId: base.trailerYoutubeId,
    record: RecordInfo(
      tmdbId: int.tryParse(base.contentId),
      score: vote is num ? vote.toDouble() : null,
      nextEpisode: nextEp,
      nextAiringAt: nextAt,
      facts: [
        if (about is Map) ...[
          if (str(about['studio']) != null)
            RecordFact('detail.about_studio', str(about['studio'])!),
          if (str(about['network']) != null)
            RecordFact('detail.about_network', str(about['network'])!),
          if (num_(about['seasons']) != null)
            RecordFact('detail.about_seasons', '${num_(about['seasons'])}'),
          if (num_(about['episodes']) != null)
            RecordFact('detail.about_episodes', '${num_(about['episodes'])}'),
          if ((num_(about['budget']) ?? 0) > 0)
            RecordFact('detail.about_budget', _money(num_(about['budget'])!)),
          if ((num_(about['revenue']) ?? 0) > 0)
            RecordFact(
              'detail.about_box_office',
              _money(num_(about['revenue'])!),
            ),
          if (str(about['collection']) != null)
            RecordFact('detail.about_collection', str(about['collection'])!),
        ],
        if (status != null && status.isNotEmpty)
          RecordFact('detail.about_status', status),
      ],
    ),
  );
}

/// $250,000,000 → "$250M"; $9,500,000 → "$9.5M".
String _money(int amount) {
  if (amount >= 1000000000) {
    return '\$${(amount / 1000000000).toStringAsFixed(1)}B';
  }
  if (amount >= 1000000) {
    final m = amount / 1000000;
    return '\$${m >= 100 ? m.round() : m.toStringAsFixed(1)}M';
  }
  return '\$${(amount / 1000).round()}K';
}
