import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

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

  LiveChannel withCategory(String value) => LiveChannel(
    id: id,
    name: name,
    streamUrl: streamUrl,
    logoUrl: logoUrl,
    country: country,
    language: language,
    category: value,
    headers: headers,
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
      // Present when the channel arrives from a flat listing rather than from
      // inside a group; withCategory still fills it in for the grouped shape.
      category: json['category']?.toString() ?? '',
      headers: switch (json['headers']) {
        final Map<dynamic, dynamic> m => {
          for (final entry in m.entries)
            if (entry.value != null) entry.key.toString(): entry.value.toString(),
        },
        _ => const {},
      },
    );
  }
}

@immutable
class LiveCategory {
  const LiveCategory({required this.name, required this.channels});

  final String name;
  final List<LiveChannel> channels;
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

  static const empty = LiveIndex(folders: [], countries: []);
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

  static const empty = LivePage(channels: [], page: 1, total: 0, hasMore: false);
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

  Future<List<LiveCategory>> lineup() async {
    final response = await _dio.get('/channels');
    final categories = (response.data as Map?)?['categories'];
    if (categories is! List) return const [];

    final out = <LiveCategory>[];
    for (final raw in categories.whereType<Map>()) {
      final name = raw['name']?.toString() ?? 'general';
      final list = raw['channels'];
      if (list is! List) continue;
      final channels = list
          .whereType<Map>()
          .map((e) => LiveChannel.fromJson(e.cast<String, dynamic>()))
          .whereType<LiveChannel>()
          .map((c) => c.withCategory(name))
          .toList(growable: false);
      if (channels.isNotEmpty) {
        out.add(LiveCategory(name: name, channels: channels));
      }
    }
    return out;
  }
}
