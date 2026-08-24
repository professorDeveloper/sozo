import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// One programme in a channel's guide.
///
/// Arrives two ways and is parsed once: inline on a channel as its `now` and
/// `next` slots, and as a row of `/channels/:id/epg`. The server sends the same
/// shape both times.
///
/// Everything but the title is optional, and the title is the only thing worth
/// refusing a slot over — an entry with no name is a blank line the UI cannot
/// draw. About a third of the line-up has no guide at all, so a null
/// [LiveProgramme] is the ordinary case here, not a failure.
@immutable
class LiveProgramme {
  const LiveProgramme({
    required this.title,
    this.id = '',
    this.start,
    this.stop,
    this.subtitle = '',
    this.description = '',
    this.category = '',
    this.icon,
    this.season,
    this.episode,
  });

  final String id;
  final String title;

  /// Episode title, tagline, or whatever the feed put in its `sub-title`.
  /// Frequently empty even where the rest of the guide is complete.
  final String subtitle;
  final String description;

  /// The programme's own genre, which is not the channel's category: a film on
  /// a news channel says "Movie" here and "News" on the channel.
  final String category;

  /// Poster or still for this programme, when the feed carried one. Separate
  /// from the channel logo, and absent far more often than present.
  final String? icon;

  /// Both usually null, and not reliably 1-based — feeds disagree — so they are
  /// carried through exactly as sent and never used in arithmetic.
  final int? season;
  final int? episode;

  /// Slot boundaries in local time, or null when the entry carried no usable
  /// timestamp.
  ///
  /// Converted with [DateTime.toLocal] on the way in, so nothing above this
  /// line has to remember to. Nullable independently of the title: a slot can
  /// legitimately name a programme without bounding it.
  final DateTime? start;
  final DateTime? stop;

  /// True when there is a real window to measure against — both ends present
  /// and in the right order. Everything time-shaped below is meaningless
  /// without it, so ask this before drawing a clock or a bar.
  bool get hasWindow => start != null && stop != null && stop!.isAfter(start!);

  Duration? get duration => hasWindow ? stop!.difference(start!) : null;

  /// How far through this slot [when] falls, from 0 to 1.
  ///
  /// Zero when the window is missing or nonsensical, on purpose: a bar drawn
  /// empty is a bar the eye skips, while a NaN or an overrun is a bar that
  /// lies. Clamped at both ends, so a stale payload whose slot already finished
  /// reads as full rather than as 1.4.
  double progressAt(DateTime when) {
    if (!hasWindow) return 0;
    final total = stop!.difference(start!).inSeconds;
    if (total <= 0) return 0;
    final gone = when.difference(start!).inSeconds;
    if (gone <= 0) return 0;
    if (gone >= total) return 1;
    return gone / total;
  }

  /// [progressAt] for this instant — and only for this instant. Anything
  /// drawing it wants a timer, not a value cached at build time.
  double get progress => progressAt(DateTime.now());

  bool isLiveAt(DateTime when) =>
      hasWindow && !when.isBefore(start!) && when.isBefore(stop!);

  bool get isLive => isLiveAt(DateTime.now());

  /// What is left of the slot, or null when it cannot be known. Never negative.
  Duration? remainingAt(DateTime when) {
    if (!hasWindow) return null;
    final left = stop!.difference(when);
    return left.isNegative ? Duration.zero : left;
  }

  /// Whether a progress bar drawn for this slot would mean anything.
  ///
  /// XMLTV feeds pad thin guides with nine-hour "Programmes" blocks; a bar that
  /// has not visibly moved since breakfast is worse than no bar. Anything under
  /// five minutes is a junction or an ident and is over before it is read.
  bool get isBarWorthy {
    final span = duration;
    return span != null && span.inMinutes >= 5 && span.inMinutes <= 360;
  }

  /// `S2 E5`, `E5`, or empty. Deliberately language-neutral: the numbers are
  /// the content, and any word around them is the UI's to localise.
  String get episodeLabel {
    final s = season;
    final e = episode;
    if (s != null && e != null) return 'S$s E$e';
    if (e != null) return 'E$e';
    if (s != null) return 'S$s';
    return '';
  }

  /// Null for anything that is not a usable slot: a missing key, an explicit
  /// null, an empty object, or an entry with no title.
  static LiveProgramme? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final title = _text(raw['title']);
    if (title.isEmpty) return null;
    final icon = _text(raw['icon']);
    return LiveProgramme(
      id: _text(raw['id']),
      title: title,
      subtitle: _text(raw['subtitle']),
      description: _text(raw['description']),
      category: _text(raw['category']),
      icon: icon.isEmpty ? null : icon,
      season: _int(raw['season']),
      episode: _int(raw['episode']),
      start: _time(raw['start']),
      stop: _time(raw['stop']),
    );
  }

  static String _text(dynamic raw) => raw == null ? '' : raw.toString().trim();

  static int? _int(dynamic raw) {
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  /// ISO 8601 in, local out.
  ///
  /// [DateTime.tryParse] returns null rather than throwing on the malformed
  /// ones, keeps the zone when the string carries `Z` or an offset, and reads a
  /// bare timestamp as local — which is what the server sends and what the
  /// viewer means. Epoch numbers are accepted too, because feeds change their
  /// minds; seconds and milliseconds are told apart by magnitude.
  static DateTime? _time(dynamic raw) {
    if (raw is String) {
      final text = raw.trim();
      if (text.isEmpty) return null;
      return DateTime.tryParse(text)?.toLocal();
    }
    if (raw is num) {
      final value = raw.toInt();
      if (value == 0) return null;
      final ms = value.abs() < 100000000000 ? value * 1000 : value;
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    }
    return null;
  }
}

/// One live channel.
@immutable
class LiveChannel {
  const LiveChannel({
    required this.id,
    required this.name,
    required this.streamUrl,
    this.logoUrl,
    this.country = '',
    this.language = '',
    this.category = '',
    this.headers = const {},
    this.now,
    this.next,
  });

  final String id;
  final String name;
  final String streamUrl;
  final String? logoUrl;
  final String country;
  final String language;

  /// Headers this stream's origin insists on, or empty.
  ///
  /// A good share of broadcast CDNs answer 403 to a request that does not
  /// present the User-Agent or Referer they expect. The server knows which
  /// channels those are; without carrying them here the player asks plainly and
  /// the channel looks simply broken.
  final Map<String, String> headers;

  /// Filled in from the group it arrived in, so a channel carries its own
  /// category once it is out of the list.
  final String category;

  /// What is on, and what follows it. Null for a channel with no guide — about
  /// a third of the line-up — and null again for a channel rebuilt from a saved
  /// favourite, since a slot is stale within the hour and is never worth
  /// persisting. Anything reading these must draw a channel that has neither.
  final LiveProgramme? now;
  final LiveProgramme? next;

  /// Whether there is anything to show under the name at all.
  bool get hasGuide => now != null || next != null;

  /// What to show as "on now" at [when], or null.
  ///
  /// The listing's `now` was correct when the page was fetched and a long
  /// session outlives it, so a `now` whose window has already closed gives way
  /// to `next` once `next` has actually started. A slot with no window at all
  /// still counts: the feed named the programme without bounding it, and a name
  /// is the part worth drawing. Null means "no guide, or a hole at this hour" —
  /// the ordinary case for about 38% of the line-up.
  LiveProgramme? slotAt(DateTime when) {
    final current = now;
    if (current != null && (!current.hasWindow || current.isLiveAt(when))) {
      return current;
    }
    final upcoming = next;
    if (upcoming != null && upcoming.hasWindow && upcoming.isLiveAt(when)) {
      return upcoming;
    }
    return null;
  }

  /// The same channel with a fresher guide, for a screen that rolls its slots
  /// forward on a timer rather than re-fetching the page.
  ///
  /// Both arguments are positional and required so that passing nothing is not
  /// a thing anyone can do by accident: this replaces the pair outright, and a
  /// null means "no slot", never "leave what was there".
  LiveChannel withGuide(LiveProgramme? nowSlot, LiveProgramme? nextSlot) =>
      LiveChannel(
        id: id,
        name: name,
        streamUrl: streamUrl,
        logoUrl: logoUrl,
        country: country,
        language: language,
        category: category,
        headers: headers,
        now: nowSlot,
        next: nextSlot,
      );

  static LiveChannel? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    final url = json['streamUrl']?.toString();
    final name = json['name']?.toString();
    if (id == null || url == null || url.isEmpty || name == null || name.isEmpty) {
      return null;
    }
    return LiveChannel(
      id: id,
      name: name,
      streamUrl: url,
      logoUrl: (json['logoUrl'] as String?)?.trim().isEmpty ?? true
          ? null
          : json['logoUrl'] as String,
      country: json['country']?.toString() ?? '',
      language: json['language']?.toString() ?? '',
      // Sent with every channel the browse endpoint returns, so a channel
      // carries its own category once it is out of the list.
      category: json['category']?.toString() ?? '',
      headers: switch (json['headers']) {
        final Map<dynamic, dynamic> m => {
          for (final entry in m.entries)
            if (entry.value != null) entry.key.toString(): entry.value.toString(),
        },
        _ => const {},
      },
      // Absent for a channel with no guide, and absent from the grouped
      // `/channels` shape entirely. Both stay null there, which is a state the
      // rest of this class already has to survive.
      now: LiveProgramme.fromJson(json['now']),
      next: LiveProgramme.fromJson(json['next']),
    );
  }
}

/// One folder in the line-up, and how much is inside it.
@immutable
class LiveFolder {
  const LiveFolder({required this.name, required this.count, this.logoUrl});

  final String name;
  final int count;
  final String? logoUrl;
}

/// One country in the line-up, and how many channels come from it.
///
/// Alongside the folders rather than instead of them: the folders answer "what
/// do I feel like watching", this answers "show me our channels", and for most
/// people opening Live TV the second question is the one they have.
@immutable
class LiveCountry {
  const LiveCountry({required this.code, required this.count});

  final String code;
  final int count;
}

/// What `/channels/categories` returns: both ways of slicing the line-up.
@immutable
class LiveIndex {
  const LiveIndex({required this.folders, required this.countries});

  final List<LiveFolder> folders;
  final List<LiveCountry> countries;
}

/// One page of channels.
@immutable
class LivePage {
  const LivePage({
    required this.channels,
    required this.page,
    required this.total,
    required this.hasMore,
  });

  final List<LiveChannel> channels;
  final int page;
  final int total;
  final bool hasMore;
}

/// One channel's guide, as `/channels/:id/epg` returns it.
///
/// An empty schedule is a normal answer, not a failure: the guide covers around
/// 62% of the line-up, and a channel outside that still plays perfectly well.
@immutable
class LiveSchedule {
  const LiveSchedule({
    required this.channelId,
    required this.channelName,
    required this.programmes,
  });

  final String channelId;
  final String channelName;

  /// Ordered by start time, earliest first, with any untimed rows at the end.
  /// Sorted here rather than trusted from the wire, because everything below
  /// depends on the order and re-sorting a few dozen rows costs nothing.
  final List<LiveProgramme> programmes;

  static const empty = LiveSchedule(
    channelId: '',
    channelName: '',
    programmes: [],
  );

  bool get isEmpty => programmes.isEmpty;
  bool get isNotEmpty => programmes.isNotEmpty;

  /// The slot covering [when], or null — including when the guide simply has a
  /// hole at that hour, which real feeds do have.
  LiveProgramme? currentAt(DateTime when) {
    for (final programme in programmes) {
      if (programme.isLiveAt(when)) return programme;
    }
    return null;
  }

  /// The first slot that starts after [when], or null.
  LiveProgramme? nextAfter(DateTime when) {
    for (final programme in programmes) {
      final start = programme.start;
      if (start != null && start.isAfter(when)) return programme;
    }
    return null;
  }

  /// What is on now, then everything still to come. What a schedule sheet
  /// actually draws — yesterday's rows are noise on a screen about tonight.
  List<LiveProgramme> from(DateTime when) {
    return programmes.where((programme) {
      if (programme.isLiveAt(when)) return true;
      final start = programme.start;
      return start != null && start.isAfter(when);
    }).toList(growable: false);
  }

  /// [fallbackId] stands in when the payload does not echo the channel back,
  /// so the schedule always knows which channel it belongs to.
  static LiveSchedule fromJson(dynamic raw, {String fallbackId = ''}) {
    if (raw is! Map) return LiveSchedule.empty;

    var id = fallbackId;
    var name = '';
    final channel = raw['channel'];
    if (channel is Map) {
      final rawId = channel['id']?.toString().trim() ?? '';
      if (rawId.isNotEmpty) id = rawId;
      name = channel['name']?.toString().trim() ?? '';
    } else if (channel is String) {
      name = channel.trim();
    }

    final rows = raw['programmes'];
    final List<LiveProgramme> programmes = rows is! List
        ? <LiveProgramme>[]
        : rows
              .map(LiveProgramme.fromJson)
              .whereType<LiveProgramme>()
              .toList();
    programmes.sort(_byStart);

    return LiveSchedule(
      channelId: id,
      channelName: name,
      programmes: List<LiveProgramme>.unmodifiable(programmes),
    );
  }

  static int _byStart(LiveProgramme a, LiveProgramme b) {
    final x = a.start;
    final y = b.start;
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return x.compareTo(y);
  }
}

/// The live TV line-up.
///
/// Grouped by the server rather than here: the TV app reads the same endpoint,
/// and two clients each applying their own grouping rules is two sets of rules
/// that drift.
///
/// Fetched a folder and a page at a time, because the whole line-up in one
/// response is fine at a thousand channels and absurd at a hundred thousand —
/// twenty megabytes of JSON a phone has to parse before it can draw anything,
/// then filter in full on every keystroke.
class LiveTvService {
  const LiveTvService({required Dio dio}) : _dio = dio;

  final Dio _dio;

  /// The folders and the countries. A few dozen rows however large the line-up
  /// behind them is.
  Future<LiveIndex> index() async {
    final response = await _dio.get('/channels/categories');
    final data = response.data as Map?;
    final raw = data?['categories'];
    final rawCountries = data?['countries'];
    return LiveIndex(
      folders: raw is! List
          ? const []
          : [
              for (final item in raw.whereType<Map>())
                if ((item['name']?.toString() ?? '').isNotEmpty)
                  LiveFolder(
                    name: item['name'].toString(),
                    count: (item['count'] as num?)?.toInt() ?? 0,
                    logoUrl: (item['logoUrl'] as String?)?.trim().isEmpty ?? true
                        ? null
                        : item['logoUrl'] as String,
                  ),
            ],
      countries: rawCountries is! List
          ? const []
          : [
              for (final item in rawCountries.whereType<Map>())
                if ((item['code']?.toString() ?? '').isNotEmpty)
                  LiveCountry(
                    code: item['code'].toString(),
                    count: (item['count'] as num?)?.toInt() ?? 0,
                  ),
            ],
    );
  }

  /// One page, optionally inside a folder or matching a search.
  ///
  /// Searching is the server's job: a client cannot filter what it never
  /// received, and paging it all in just to filter locally is the same twenty
  /// megabytes with extra steps.
  Future<LivePage> browse({
    String? category,
    String? country,
    String? search,
    int page = 1,
    int limit = 40,
  }) async {
    final response = await _dio.get(
      '/channels/browse',
      queryParameters: {
        'page': page,
        'limit': limit,
        if (category != null && category.isNotEmpty) 'category': category,
        if (country != null && country.isNotEmpty) 'country': country,
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      },
    );
    final data = response.data as Map?;
    final raw = data?['channels'];
    return LivePage(
      channels: raw is! List
          ? const []
          : raw
                .whereType<Map>()
                .map((e) => LiveChannel.fromJson(e.cast<String, dynamic>()))
                .whereType<LiveChannel>()
                .toList(growable: false),
      page: (data?['page'] as num?)?.toInt() ?? page,
      total: (data?['total'] as num?)?.toInt() ?? 0,
      hasMore: data?['hasMore'] == true,
    );
  }

  /// One channel's guide, [hours] ahead.
  ///
  /// Separate from [browse] on purpose: a page of forty channels does not want
  /// forty schedules hanging off it, so the listing carries only the two slots
  /// a tile can show and the full day is read once, for the one channel
  /// somebody actually opened.
  ///
  /// Returns an empty schedule for a channel with no guide, or for a response
  /// shaped in a way this does not recognise. Network and HTTP failures throw,
  /// as they do everywhere else in this service — the caller decides whether a
  /// missing guide is worth saying out loud, and on this screen it is not.
  Future<LiveSchedule> schedule(String channelId, {int hours = 24}) async {
    final id = channelId.trim();
    if (id.isEmpty) return LiveSchedule.empty;
    final response = await _dio.get(
      // Encoded because channel ids come from the feed rather than from us and
      // routinely contain dots, and occasionally worse.
      '/channels/${Uri.encodeComponent(id)}/epg',
      queryParameters: {'hours': hours.clamp(1, 168).toInt()},
    );
    return LiveSchedule.fromJson(response.data, fallbackId: id);
  }
}
