import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:soplay/features/jellyfin/data/jellyfin_api.dart';
import 'package:soplay/features/jellyfin/data/jellyfin_server_store.dart';
import 'package:soplay/features/jellyfin/domain/jellyfin_server.dart';
import 'package:soplay/features/jellyfin/domain/jellyfin_urls.dart';

/// What the player needs to report a stream back to the server it came from.
class JellyfinPlaySession {
  const JellyfinPlaySession({
    required this.serverId,
    required this.itemId,
    required this.mediaSourceId,
    required this.playSessionId,
    this.resumeAt = Duration.zero,
  });

  final String serverId;
  final String itemId;
  final String mediaSourceId;
  final String playSessionId;
  final Duration resumeAt;

  /// Which of Jellyfin's three methods produced [url]; the server shows it in
  /// its dashboard and uses it to decide whether a transcode must be killed.
  static String playMethodFor(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    if (path.endsWith('.m3u8')) return 'Transcode';
    return url.contains('static=true') ? 'DirectPlay' : 'DirectStream';
  }
}

/// Translates a Jellyfin server into the JSON shapes the on-device hosts emit
/// (see `MangayomiBridge`), so `jf:` rides the same repository branches as
/// `cs:`, `an:`, `mn:` and `my:`. Everything runs in Dart against the server's
/// REST API; nothing touches the Sozo backend.
class JellyfinBridge {
  JellyfinBridge({
    required this.api,
    required this.store,
    String Function(String key)? label,
  }) : _label = label ?? ((k) => k.tr());

  final JellyfinApi api;
  final JellyfinServerStore store;
  final String Function(String key) _label;

  static const String icon =
      'https://avatars.githubusercontent.com/u/45698031?s=200&v=4';

  static const int pageSize = 40;

  /// Library kinds that hold something the video player can open. Music,
  /// books, photos and live TV have their own clients.
  static const Set<String?> playableCollections = {
    'movies',
    'tvshows',
    'mixed',
    'homevideos',
    null,
  };

  static String bare(String providerId) =>
      providerId.startsWith(JellyfinServer.prefix)
      ? providerId.substring(JellyfinServer.prefix.length)
      : providerId;

  final Map<String, JellyfinPlaySession> _sessions = {};

  final Map<String, ({DateTime at, Future<Map<String, dynamic>> value})>
  _loads = {};

  List<Map<String, dynamic>> listProviders() => [
    for (final s in store.servers())
      {
        'id': s.providerId,
        'name': s.name,
        'lang': 'all',
        'baseUrl': s.baseUrl,
        'icon': icon,
        'repo': s.host,
        'mode': 'client',
        'group': 'jellyfin',
      },
  ];

  String describe(Object error) {
    if (error is JellyfinException) {
      return switch (error.kind) {
        JellyfinErrorKind.unreachable => _label('jellyfin.error_unreachable'),
        JellyfinErrorKind.unauthorized => _label('jellyfin.error_session'),
        JellyfinErrorKind.notJellyfin => _label('jellyfin.error_not_jellyfin'),
        JellyfinErrorKind.server =>
          '${_label('jellyfin.error_server')} (${error.detail})',
      };
    }
    return error.toString();
  }

  Map<String, dynamic> _missing(String id) => {
    'provider': '${JellyfinServer.prefix}$id',
    'items': const <Map<String, dynamic>>[],
    'sections': const <Map<String, dynamic>>[],
    'error': _label('jellyfin.error_server_removed'),
  };

  // --- cards ---------------------------------------------------------------

  /// One item as a card. An episode opens its series: the detail page and the
  /// history row are about the show, not a single episode.
  @visibleForTesting
  static Map<String, dynamic> card(JellyfinServer s, Map<String, dynamic> it) {
    final base = s.baseUrl;
    final type = it['Type']?.toString() ?? '';
    final isEpisode = type == 'Episode';
    final id = it['Id']?.toString() ?? '';
    final seriesId = it['SeriesId']?.toString();
    final target = isEpisode && seriesId != null && seriesId.isNotEmpty
        ? seriesId
        : id;

    final tags = it['ImageTags'] is Map ? it['ImageTags'] as Map : const {};
    String? poster;
    if (isEpisode && it['SeriesPrimaryImageTag'] != null && seriesId != null) {
      poster = JellyfinUrls.image(
        base,
        seriesId,
        tag: it['SeriesPrimaryImageTag'].toString(),
      );
    } else if (tags['Primary'] != null) {
      poster = JellyfinUrls.image(base, id, tag: tags['Primary'].toString());
    }

    String? backdrop;
    final own = it['BackdropImageTags'];
    final parent = it['ParentBackdropImageTags'];
    if (own is List && own.isNotEmpty) {
      backdrop = JellyfinUrls.image(
        base,
        id,
        type: 'Backdrop',
        index: 0,
        tag: own.first.toString(),
        maxWidth: 1280,
      );
    } else if (parent is List &&
        parent.isNotEmpty &&
        it['ParentBackdropItemId'] != null) {
      backdrop = JellyfinUrls.image(
        base,
        it['ParentBackdropItemId'].toString(),
        type: 'Backdrop',
        index: 0,
        tag: parent.first.toString(),
        maxWidth: 1280,
      );
    }

    final rating = it['CommunityRating'];
    return {
      'provider': s.providerId,
      'externalId': target,
      'title': isEpisode
          ? (it['SeriesName'] ?? it['Name'] ?? '').toString()
          : (it['Name'] ?? '').toString(),
      'description': isEpisode
          ? episodeLabel(it)
          : (it['Overview'] ?? '').toString(),
      'slug': target,
      'contentUrl': target,
      'thumbnail': poster,
      'banner': backdrop,
      'year': (it['ProductionYear'] as num?)?.toInt(),
      if (rating is num) 'rating': rating.round(),
      'type': isEpisode ? 'Series' : type,
    };
  }

  static List<Map<String, dynamic>> _cards(
    JellyfinServer s,
    Iterable<Map<String, dynamic>> items,
  ) {
    final seen = <String>{};
    return [
      for (final it in items)
        if (card(s, it) case final c
            when (c['contentUrl'] as String).isNotEmpty &&
                seen.add(c['contentUrl'] as String))
          c,
    ];
  }

  /// "S1 E3 · Title". Specials (season 0) read "SP".
  static String episodeLabel(Map<String, dynamic> ep) {
    final season = (ep['ParentIndexNumber'] as num?)?.toInt();
    final number = (ep['IndexNumber'] as num?)?.toInt();
    final name = (ep['Name'] ?? '').toString().trim();
    final parts = <String>[
      if (season != null) season == 0 ? 'SP' : 'S$season',
      if (number != null) 'E$number',
    ];
    final prefix = parts.join(' ');
    if (prefix.isEmpty) return name;
    return name.isEmpty ? prefix : '$prefix · $name';
  }

  // --- home ----------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _libraries(JellyfinServer s) async => [
    for (final v in await api.views(s))
      if (playableCollections.contains(v['CollectionType']?.toString()) &&
          v['Id'] != null &&
          s.shows(v['Id'].toString()))
        v,
  ];

  Future<List<Map<String, dynamic>>> _soft(
    Future<List<Map<String, dynamic>>> call,
  ) => call.catchError((Object _) => const <Map<String, dynamic>>[]);

  Future<Map<String, dynamic>> getMainPage(String serverId) async {
    final s = store.byId(serverId);
    if (s == null) return _missing(serverId);
    try {
      final libraries = await _libraries(s);
      final resumeF = _soft(api.resume(s));
      final nextUpF = _soft(api.nextUp(s));
      final latestF = [
        for (final lib in libraries) _soft(api.latest(s, lib['Id'].toString())),
      ];
      final resume = await resumeF;
      final nextUp = await nextUpF;
      final latest = await Future.wait(latestF);
      return buildHome(
        s,
        libraries: libraries,
        resume: resume,
        nextUp: nextUp,
        latest: latest,
        label: _label,
      );
    } catch (e) {
      return {
        'provider': s.providerId,
        'banner': const [],
        'sections': const [],
        'error': describe(e),
      };
    }
  }

  @visibleForTesting
  static Map<String, dynamic> buildHome(
    JellyfinServer s, {
    required List<Map<String, dynamic>> libraries,
    required List<Map<String, dynamic>> resume,
    required List<Map<String, dynamic>> nextUp,
    required List<List<Map<String, dynamic>>> latest,
    required String Function(String) label,
  }) {
    final sections = <Map<String, dynamic>>[];
    void add(String key, String title, String slug, List<Map> items) {
      if (items.isEmpty) return;
      sections.add({
        'key': key,
        'label': title,
        'viewAll': {'type': 'jf', 'slug': slug},
        'items': items,
      });
    }

    add(
      'jf-resume',
      label('jellyfin.continue_watching'),
      'resume',
      _cards(s, resume),
    );
    add('jf-nextup', label('jellyfin.next_up'), 'nextup', _cards(s, nextUp));
    final banner = <Map<String, dynamic>>[];
    for (var i = 0; i < libraries.length && i < latest.length; i++) {
      final lib = libraries[i];
      final cards = _cards(s, latest[i]);
      add(
        'jf-lib-${lib['Id']}',
        (lib['Name'] ?? '').toString(),
        'lib:${lib['Id']}',
        cards,
      );
      banner.addAll(cards.where((c) => c['banner'] != null).take(4));
    }
    return {
      'provider': s.providerId,
      'banner': banner.take(10).toList(),
      'sections': sections,
      if (sections.isEmpty) 'error': label('jellyfin.empty_server'),
    };
  }

  /// A "see all" page. Slugs: `resume`, `nextup`, `lib:<viewId>`,
  /// `genre:<genreId>`.
  Future<Map<String, dynamic>> getSection(
    String serverId,
    String slug, {
    int page = 1,
  }) async {
    final s = store.byId(serverId);
    if (s == null) {
      return {..._missing(serverId), 'page': page, 'totalPages': page};
    }
    List<Map<String, dynamic>> items;
    var total = 0;
    if (slug == 'resume' || slug == 'nextup') {
      items = page > 1
          ? const []
          : slug == 'resume'
          ? await api.resume(s, limit: 100)
          : await api.nextUp(s, limit: 100);
      total = items.length;
    } else {
      final lib = slug.startsWith('lib:') ? slug.substring(4) : null;
      final genre = slug.startsWith('genre:') ? slug.substring(6) : null;
      final res = await api.items(
        s,
        parentId: lib,
        genreId: genre,
        includeTypes: 'Movie,Series,Video',
        start: (page - 1) * pageSize,
        limit: pageSize,
      );
      items = res.items;
      total = res.total;
    }
    return {
      'provider': s.providerId,
      'items': _cards(s, items),
      'page': page,
      'totalPages': total <= 0 ? page : ((total + pageSize - 1) ~/ pageSize),
    };
  }

  Future<Map<String, dynamic>> search(
    String serverId,
    String query, {
    int page = 1,
  }) async {
    final s = store.byId(serverId);
    if (s == null) return _missing(serverId);
    try {
      final res = await api.items(
        s,
        searchTerm: query,
        includeTypes: 'Movie,Series,Episode,Video',
        start: (page - 1) * pageSize,
        limit: pageSize,
      );
      return {
        'provider': s.providerId,
        'items': _cards(s, res.items),
        'query': query,
        'page': page,
        'totalPages': res.total <= 0
            ? page
            : ((res.total + pageSize - 1) ~/ pageSize),
      };
    } catch (e) {
      return {
        'provider': s.providerId,
        'items': const [],
        'query': query,
        'page': page,
        'totalPages': page,
        'error': describe(e),
      };
    }
  }

  /// In the `GenreModel` shape; the slug is the genre id, which
  /// [getSection] takes as `genre:<id>`.
  Future<List<Map<String, dynamic>>> genres(String serverId) async {
    final s = store.byId(serverId);
    if (s == null) return const [];
    return [
      for (final g in await api.genres(s))
        if (g['Id'] != null)
          {
            'provider': s.providerId,
            'slug': g['Id'].toString(),
            'name': (g['Name'] ?? '').toString(),
            'url': '',
            'image':
                (g['ImageTags'] is Map &&
                    (g['ImageTags'] as Map)['Primary'] != null)
                ? JellyfinUrls.image(
                    s.baseUrl,
                    g['Id'].toString(),
                    tag: (g['ImageTags'] as Map)['Primary'].toString(),
                  )
                : '',
          },
    ];
  }

  // --- detail --------------------------------------------------------------

  /// Detail and episodes are asked for back to back by the detail page; one
  /// round of requests serves both.
  Future<Map<String, dynamic>> load(String serverId, String itemId) {
    final key = '$serverId|$itemId';
    final cached = _loads[key];
    final now = DateTime.now();
    if (cached != null && now.difference(cached.at).inSeconds < 30) {
      return cached.value;
    }
    final future = _load(serverId, itemId);
    _loads[key] = (at: now, value: future);
    future.then((m) {
      if (m.isEmpty || m['error'] != null) _loads.remove(key);
    });
    if (_loads.length > 50) _loads.remove(_loads.keys.first);
    return future;
  }

  Future<Map<String, dynamic>> _load(String serverId, String itemId) async {
    final s = store.byId(serverId);
    if (s == null) return _missing(serverId);
    try {
      var item = await api.item(s, itemId);
      final type = item['Type']?.toString();
      // A search hit or an old history row can point at an episode or a
      // season; the page is always the show's.
      if ((type == 'Episode' || type == 'Season') && item['SeriesId'] != null) {
        item = await api.item(s, item['SeriesId'].toString());
      }
      final id = item['Id']?.toString() ?? itemId;
      final isSeries = item['Type'] == 'Series';
      final episodesF = isSeries
          ? api.episodes(s, id)
          : Future.value(const <Map<String, dynamic>>[]);
      final similarF = _soft(api.similar(s, id));
      return buildDetail(
        s,
        item,
        episodes: await episodesF,
        similar: await similarF,
      );
    } catch (e) {
      return {
        'provider': s.providerId,
        'contentUrl': itemId,
        'episodes': const [],
        'error': describe(e),
      };
    }
  }

  @visibleForTesting
  static Map<String, dynamic> buildDetail(
    JellyfinServer s,
    Map<String, dynamic> item, {
    List<Map<String, dynamic>> episodes = const [],
    List<Map<String, dynamic>> similar = const [],
  }) {
    final base = s.baseUrl;
    final id = item['Id']?.toString() ?? '';
    final isSeries = item['Type'] == 'Series';
    final tags = item['ImageTags'] is Map ? item['ImageTags'] as Map : const {};
    final backdrops = item['BackdropImageTags'];
    final people = (item['People'] as List? ?? const []).whereType<Map>();

    final eps = <Map<String, dynamic>>[];
    if (isSeries) {
      final ordered = [
        for (final e in episodes)
          if (e['LocationType'] != 'Virtual' && e['Id'] != null) e,
      ]..sort(compareEpisodes);
      for (var i = 0; i < ordered.length; i++) {
        final e = ordered[i];
        final eTags = e['ImageTags'] is Map ? e['ImageTags'] as Map : const {};
        eps.add({
          'episode': i + 1,
          'label': episodeLabel(e),
          'mediaRef': e['Id'].toString(),
          if (eTags['Primary'] != null)
            'image': JellyfinUrls.image(
              base,
              e['Id'].toString(),
              tag: eTags['Primary'].toString(),
            ),
          'overview': ?e['Overview']?.toString(),
          'runtime': ?_runtime(e['RunTimeTicks']),
          'airdate': ?_date(e['PremiereDate']),
        });
      }
    } else if (id.isNotEmpty) {
      eps.add({
        'episode': 1,
        'label': (item['Name'] ?? '').toString(),
        'mediaRef': id,
        'runtime': ?_runtime(item['RunTimeTicks']),
      });
    }

    final directors = [
      for (final p in people)
        if (p['Type'] == 'Director' && p['Name'] != null) p['Name'].toString(),
    ];
    final locations = item['ProductionLocations'];
    return {
      'provider': s.providerId,
      'contentId': id,
      'contentUrl': id,
      'title': (item['Name'] ?? '').toString(),
      'description': (item['Overview'] ?? '').toString(),
      'thumbnail': tags['Primary'] != null
          ? JellyfinUrls.image(base, id, tag: tags['Primary'].toString())
          : null,
      'banner': backdrops is List && backdrops.isNotEmpty
          ? JellyfinUrls.image(
              base,
              id,
              type: 'Backdrop',
              index: 0,
              tag: backdrops.first.toString(),
              maxWidth: 1280,
            )
          : null,
      'year': (item['ProductionYear'] as num?)?.toInt(),
      if (!isSeries) 'duration': ?_runtime(item['RunTimeTicks']),
      if (locations is List && locations.isNotEmpty)
        'country': locations.first.toString(),
      if (directors.isNotEmpty) 'director': directors.take(3).join(', '),
      'genres': [
        for (final g in (item['Genres'] as List? ?? const [])) g.toString(),
      ],
      'type': isSeries ? 'Series' : 'Movie',
      'isSerial': isSeries,
      'cast': [
        for (final p in people.where((p) => p['Type'] == 'Actor').take(20))
          {
            'id': (p['Id'] ?? '').toString(),
            'name': (p['Name'] ?? '').toString(),
            'image': p['PrimaryImageTag'] != null && p['Id'] != null
                ? JellyfinUrls.image(
                    base,
                    p['Id'].toString(),
                    tag: p['PrimaryImageTag'].toString(),
                    maxWidth: 200,
                  )
                : '',
          },
      ],
      'related': _cards(s, similar),
      'episodes': eps,
    };
  }

  /// Season order, specials last, then episode number.
  @visibleForTesting
  static int compareEpisodes(Map a, Map b) {
    int season(Map e) {
      final n = (e['ParentIndexNumber'] as num?)?.toInt();
      return n == null || n == 0 ? 1 << 20 : n;
    }

    int number(Map e) => (e['IndexNumber'] as num?)?.toInt() ?? 1 << 20;
    final bySeason = season(a).compareTo(season(b));
    return bySeason != 0 ? bySeason : number(a).compareTo(number(b));
  }

  static String? _runtime(Object? ticks) {
    final d = JellyfinUrls.ticksToDuration(ticks);
    if (d.inMinutes <= 0) return null;
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    final m = d.inMinutes % 60;
    return m == 0 ? '${d.inHours}h' : '${d.inHours}h ${m}m';
  }

  static String? _date(Object? iso) {
    final text = iso?.toString() ?? '';
    return text.length >= 10 ? text.substring(0, 10) : null;
  }

  // --- playback ------------------------------------------------------------

  /// What Sozo's players decode. Anything outside it is transcoded to
  /// H.264/AAC HLS by the server.
  static Map<String, dynamic> deviceProfile() => {
    'Name': 'Sozo',
    'MaxStreamingBitrate': 120000000,
    'MaxStaticBitrate': 120000000,
    'DirectPlayProfiles': [
      {
        'Type': 'Video',
        'Container': 'mp4,m4v,mkv,webm,mov,ts,m2ts',
        'VideoCodec': 'h264,hevc,vp9,av1',
        'AudioCodec': 'aac,mp3,opus,flac,ac3,eac3,vorbis,alac',
      },
    ],
    'TranscodingProfiles': [
      {
        'Type': 'Video',
        'Container': 'ts',
        'Protocol': 'hls',
        'VideoCodec': 'h264',
        'AudioCodec': 'aac',
        'Context': 'Streaming',
        'MaxAudioChannels': '2',
        'MinSegments': 1,
        'BreakOnNonKeyFrames': true,
      },
    ],
    'SubtitleProfiles': [
      for (final f in ['vtt', 'srt', 'subrip', 'ass', 'ssa'])
        {'Format': f, 'Method': 'External'},
    ],
    'ContainerProfiles': const [],
    'CodecProfiles': const [],
  };

  Future<Map<String, dynamic>> loadLinks(
    String serverId,
    String mediaRef,
  ) async {
    final s = store.byId(serverId);
    if (s == null) return _missing(serverId);
    try {
      final infoF = api.playbackInfo(s, mediaRef, {
        'UserId': s.userId,
        'MaxStreamingBitrate': 120000000,
        'EnableDirectPlay': true,
        'EnableDirectStream': true,
        'EnableTranscoding': true,
        'AutoOpenLiveStream': false,
        'DeviceProfile': deviceProfile(),
      });
      final itemF = api
          .item(s, mediaRef)
          .catchError((Object _) => const <String, dynamic>{});
      final info = await infoF;
      final item = await itemF;
      final built = buildLinks(
        s,
        itemId: mediaRef,
        info: info,
        item: item,
        deviceId: api.deviceId,
        authHeader: api.authHeader(s.accessToken),
        label: _label,
      );
      final session = built.session;
      if (session != null) {
        _sessions[JellyfinUrls.normalizeId(mediaRef)] = session;
      }
      return built.links;
    } catch (e) {
      return {'videoSources': const [], 'error': describe(e)};
    }
  }

  /// The session a stream URL belongs to, if it came from [loadLinks].
  JellyfinPlaySession? sessionFor(String url) {
    final id = JellyfinUrls.itemIdFromStreamUrl(url);
    return id == null ? null : _sessions[id];
  }

  @visibleForTesting
  void remember(JellyfinPlaySession session) =>
      _sessions[JellyfinUrls.normalizeId(session.itemId)] = session;

  static const List<({int height, int bitrate})> _steps = [
    (height: 1080, bitrate: 8000000),
    (height: 720, bitrate: 4000000),
    (height: 480, bitrate: 1500000),
  ];

  static const Set<String> _imageSubtitleCodecs = {
    'pgssub',
    'pgs',
    'hdmv_pgs_subtitle',
    'dvdsub',
    'dvd_subtitle',
    'dvbsub',
    'dvb_subtitle',
    'vobsub',
  };

  /// PlaybackInfo → the host `loadLinks` shape, best source first: the file
  /// itself when the server allows it, then HLS transcodes stepping down.
  @visibleForTesting
  static ({Map<String, dynamic> links, JellyfinPlaySession? session})
  buildLinks(
    JellyfinServer s, {
    required String itemId,
    required Map<String, dynamic> info,
    required Map<String, dynamic> item,
    required String deviceId,
    required String authHeader,
    required String Function(String) label,
  }) {
    final base = s.baseUrl;
    final key = JellyfinUrls.keyParam(s.version);
    final headers = {'Authorization': authHeader};
    final errorCode = info['ErrorCode']?.toString();
    final sources = [
      for (final m in (info['MediaSources'] as List? ?? const []))
        if (m is Map) Map<String, dynamic>.from(m),
    ];
    if (sources.isEmpty) {
      return (
        links: {
          'videoSources': const [],
          'error': errorCode == null || errorCode.isEmpty
              ? label('jellyfin.error_no_stream')
              : '${label('jellyfin.error_no_stream')} ($errorCode)',
        },
        session: null,
      );
    }
    final media = sources.firstWhere(
      (m) => m['Id']?.toString() == itemId,
      orElse: () => sources.first,
    );
    final msid = media['Id']?.toString() ?? itemId;
    final playSession = info['PlaySessionId']?.toString() ?? '';
    final streams = [
      for (final st in (media['MediaStreams'] as List? ?? const []))
        if (st is Map) Map<String, dynamic>.from(st),
    ];
    final video = streams.where((st) => st['Type'] == 'Video').firstOrNull;
    final height = (video?['Height'] as num?)?.toInt();
    final codec = video?['Codec']?.toString().toLowerCase();
    final audioIndex = (media['DefaultAudioStreamIndex'] as num?)?.toInt();

    final out = <Map<String, dynamic>>[];
    final direct =
        media['SupportsDirectPlay'] == true ||
        media['SupportsDirectStream'] == true;
    if (direct) {
      out.add({
        'quality': height != null
            ? '${height}p · ${label('jellyfin.quality_original')}'
            : label('jellyfin.quality_original'),
        'videoUrl': JellyfinUrls.directStream(
          base: base,
          itemId: itemId,
          mediaSourceId: msid,
          container: media['Container']?.toString() ?? '',
          token: s.accessToken,
          keyParam: key,
          deviceId: deviceId,
          playSessionId: playSession,
          tag: media['ETag']?.toString(),
        ),
        'type': 'mp4',
        'height': ?height,
        'codec': ?codec,
        'sizeBytes': ?(media['Size'] as num?)?.toInt(),
        'host': s.name,
        'isDefault': true,
        'accessible': true,
        'headers': headers,
      });
    }

    final transcodeUrl = media['TranscodingUrl']?.toString();
    if (transcodeUrl != null && transcodeUrl.isNotEmpty) {
      out.add({
        'quality': label('jellyfin.quality_auto'),
        'videoUrl': JellyfinUrls.withKey(
          JellyfinUrls.absolute(base, transcodeUrl),
          key,
          s.accessToken,
        ),
        'type': 'hls',
        'codec': 'h264',
        'host': s.name,
        'isDefault': !direct,
        'accessible': true,
        'headers': headers,
      });
    }

    final ceiling = height ?? 1080;
    for (final step in _steps) {
      if (step.height > ceiling && step.height != _steps.last.height) continue;
      out.add({
        'quality': '${step.height}p · ${label('jellyfin.quality_transcode')}',
        'videoUrl': JellyfinUrls.hls(
          base: base,
          itemId: itemId,
          mediaSourceId: msid,
          token: s.accessToken,
          keyParam: key,
          deviceId: deviceId,
          videoBitrate: step.bitrate,
          maxHeight: step.height,
          playSessionId: playSession,
          audioStreamIndex: audioIndex,
        ),
        'type': 'hls',
        'height': step.height,
        'codec': 'h264',
        'host': s.name,
        'isDefault': false,
        'accessible': true,
        'headers': headers,
      });
    }

    final defaultSub = (media['DefaultSubtitleStreamIndex'] as num?)?.toInt();
    final subtitles = <Map<String, dynamic>>[];
    for (final st in streams) {
      if (st['Type'] != 'Subtitle') continue;
      final subCodec = st['Codec']?.toString().toLowerCase() ?? '';
      if (_imageSubtitleCodecs.contains(subCodec)) continue;
      if (st['IsTextSubtitleStream'] == false) continue;
      final index = (st['Index'] as num?)?.toInt();
      if (index == null) continue;
      final delivery = st['DeliveryUrl']?.toString();
      final file = delivery != null && delivery.isNotEmpty
          ? JellyfinUrls.withKey(
              JellyfinUrls.absolute(base, delivery),
              key,
              s.accessToken,
            )
          : JellyfinUrls.subtitle(
              base: base,
              itemId: itemId,
              mediaSourceId: msid,
              index: index,
              token: s.accessToken,
              keyParam: key,
            );
      subtitles.add({
        'label':
            (st['DisplayTitle'] ?? st['Language'] ?? 'Subtitle ${index + 1}')
                .toString(),
        'file': file,
        'default': st['IsDefault'] == true || index == defaultSub,
        'headers': headers,
      });
    }

    final userData = item['UserData'];
    // Position wins over the played flag: a rewatch in progress is both, and
    // Jellyfin's own clients resume it.
    final resume = userData is Map
        ? JellyfinUrls.ticksToDuration(userData['PlaybackPositionTicks'])
        : Duration.zero;

    final first = out.isNotEmpty ? out.first : null;
    return (
      links: {
        'videoUrl': first?['videoUrl'],
        'type': first?['type'],
        'headers': headers,
        'videoSources': out,
        'subtitles': subtitles,
      },
      session: JellyfinPlaySession(
        serverId: s.id,
        itemId: itemId,
        mediaSourceId: msid,
        playSessionId: playSession,
        resumeAt: resume,
      ),
    );
  }
}
