import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:soplay/features/detail/domain/entities/playback_entity.dart';
import 'package:soplay/features/detail/domain/usecases/get_episodes_usecase.dart';
import 'package:soplay/features/detail/domain/usecases/resolve_media_usecase.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/search/domain/entities/cross_search_result.dart';
import 'package:soplay/features/search/domain/services/cross_search_engine.dart';

/// How far a source got before it stopped working.
///
/// Ordered, and the order is the pipeline: a source that fails at [stream] got
/// through [catalogue] and [detail] first. That is the whole value of the
/// thing — "AnimeKAI is broken" and "AnimeKAI lists everything and hands out
/// links that 403" are different problems with different fixes, and from the
/// app they look identical.
enum ProbeStage {
  /// Searching the source returned something.
  catalogue,

  /// A title from that search opened, with episodes or a film to play.
  detail,

  /// An episode resolved to an actual media URL.
  stream,

  /// That URL answered. This is the only stage that proves playback.
  playback,
}

/// What happened at a stage.
enum ProbeOutcome {
  /// Reached and working.
  ok,

  /// Reached, answered, and had nothing — not the same as broken. A film site
  /// that has never heard of the probe title is healthy and unhelpful.
  empty,

  /// Did not work.
  failed,

  /// Not attempted, because an earlier stage stopped the run.
  skipped,
}

class ProbeStep {
  const ProbeStep({
    required this.stage,
    required this.outcome,
    this.detail = '',
    this.millis = 0,
  });

  final ProbeStage stage;
  final ProbeOutcome outcome;

  /// Why, in the source's own words where there are any. Never a made-up
  /// summary: an HTTP status or the search leg's own message beats "failed".
  final String detail;

  final int millis;

  bool get isOk => outcome == ProbeOutcome.ok;
}

/// The result of testing one source.
class ProviderProbeResult {
  const ProviderProbeResult({
    required this.providerId,
    required this.providerName,
    required this.query,
    required this.steps,
    required this.millis,
  });

  final String providerId;
  final String providerName;

  /// The search term used. Shown, because a source that has nothing for it is
  /// reporting on the term as much as on itself.
  final String query;

  final List<ProbeStep> steps;
  final int millis;

  ProbeStep? stepFor(ProbeStage stage) {
    for (final s in steps) {
      if (s.stage == stage) return s;
    }
    return null;
  }

  /// True only when a media URL actually answered. Anything less is not proof.
  bool get playable => stepFor(ProbeStage.playback)?.isOk ?? false;

  /// The step a reader should look at: the first that is not ok, else the last.
  ProbeStep get verdict {
    for (final s in steps) {
      if (!s.isOk) return s;
    }
    return steps.last;
  }
}

/// Testing whether a source still works, all the way to a playable URL.
///
/// The app already fails one stage at a time — a source lists titles fine and
/// then hands out links that 403, or answers search and 504s on detail — and a
/// viewer meets all of that as the same blank error. Every piece needed to tell
/// them apart already exists as a use case, so this is the sequence, not new
/// machinery.
///
/// It deliberately ends on a real HTTP request for the media. Everything short
/// of that has been seen to succeed against a source that cannot play a frame:
/// the catalogue is a different host from the CDN, the token is minted
/// separately from the link, and expiry is measured in minutes.
class ProviderProbe {
  ProviderProbe({
    required CrossSearchEngine engine,
    required GetEpisodesUseCase episodes,
    required ResolveMediaUseCase resolve,
    required Dio dio,
  })  : _engine = engine,
        _episodes = episodes,
        _resolve = resolve,
        _dio = dio;

  static const String _tag = '[probe]';

  final CrossSearchEngine _engine;
  final GetEpisodesUseCase _episodes;
  final ResolveMediaUseCase _resolve;
  final Dio _dio;

  /// Search terms, by category.
  ///
  /// Two, not one, and the second is only tried when the first returns nothing:
  /// these catalogues disagree about everything including alphabet, and a
  /// single term turns "does not carry this show" into "is broken". Short
  /// enough that a source which answers any query with its recent uploads —
  /// common, and useful here — satisfies the stage immediately.
  static const Map<String, List<String>> probeTerms = {
    'anime': ['one piece', 'naruto'],
    'manga': ['one piece', 'naruto'],
  };
  static const List<String> fallbackTerms = ['man', 'love'];

  static List<String> termsFor(String category) =>
      probeTerms[category] ?? fallbackTerms;

  /// Only the first few bytes. Enough to know the CDN will serve this client,
  /// with its headers, right now — and not a download of the episode onto
  /// somebody's mobile data to find out.
  static const Duration _reachTimeout = Duration(seconds: 12);

  Future<ProviderProbeResult> run(ProviderEntity provider) async {
    final total = Stopwatch()..start();
    final steps = <ProbeStep>[];
    final ref = ProviderRef.fromEntity(provider);
    var query = termsFor(provider.category).first;

    // --- catalogue -------------------------------------------------------
    final searchSw = Stopwatch()..start();
    var items = const <_Candidate>[];
    var searchDetail = '';
    var searchFailed = false;

    for (final term in termsFor(provider.category)) {
      query = term;
      final result = await _searchOnce(ref, term);
      if (result == null) {
        searchFailed = true;
        searchDetail = 'no answer';
        break;
      }
      // `empty` is an answer, not a failure — the leg ran and the source had
      // nothing. Only a timeout or an error means it did not work.
      if (result.status == ProviderSearchStatus.timeout ||
          result.status == ProviderSearchStatus.error) {
        searchFailed = true;
        searchDetail = result.message.isEmpty
            ? (result.status == ProviderSearchStatus.timeout
                ? 'timed out'
                : 'search failed')
            : result.message;
        break;
      }
      searchFailed = false;
      searchDetail = '';
      if (result.hasItems) {
        items = result.items
            .map((i) => _Candidate(url: i.url, title: i.title))
            .toList();
        break;
      }
    }

    if (searchFailed) {
      steps.add(ProbeStep(
        stage: ProbeStage.catalogue,
        outcome: ProbeOutcome.failed,
        detail: searchDetail,
        millis: searchSw.elapsedMilliseconds,
      ));
      return _finish(provider, query, steps, total, from: ProbeStage.detail);
    }

    if (items.isEmpty) {
      // Answered, had nothing. Reported as its own outcome rather than as a
      // failure, because calling a working source broken is the one result
      // that would make this tool worse than no tool.
      steps.add(ProbeStep(
        stage: ProbeStage.catalogue,
        outcome: ProbeOutcome.empty,
        detail: 'nothing matched "$query"',
        millis: searchSw.elapsedMilliseconds,
      ));
      return _finish(provider, query, steps, total, from: ProbeStage.detail);
    }

    steps.add(ProbeStep(
      stage: ProbeStage.catalogue,
      outcome: ProbeOutcome.ok,
      detail: '${items.length} results',
      millis: searchSw.elapsedMilliseconds,
    ));

    // --- detail ----------------------------------------------------------
    final detailSw = Stopwatch()..start();
    final playback = (await _episodes(items.first.url, provider: provider.id))
        .getOrNull();

    if (playback == null) {
      steps.add(ProbeStep(
        stage: ProbeStage.detail,
        outcome: ProbeOutcome.failed,
        detail: 'could not open "${items.first.title}"',
        millis: detailSw.elapsedMilliseconds,
      ));
      return _finish(provider, query, steps, total, from: ProbeStage.stream);
    }

    final hasEpisodes = playback.episodes.isNotEmpty;
    final hasDirect =
        playback.videoSources.isNotEmpty || (playback.playerSrc ?? '').isNotEmpty;

    if (!hasEpisodes && !hasDirect) {
      steps.add(ProbeStep(
        stage: ProbeStage.detail,
        outcome: ProbeOutcome.empty,
        detail: 'opened, but nothing to play',
        millis: detailSw.elapsedMilliseconds,
      ));
      return _finish(provider, query, steps, total, from: ProbeStage.stream);
    }

    steps.add(ProbeStep(
      stage: ProbeStage.detail,
      outcome: ProbeOutcome.ok,
      detail: hasEpisodes ? '${playback.episodes.length} episodes' : 'film',
      millis: detailSw.elapsedMilliseconds,
    ));

    // --- stream ----------------------------------------------------------
    final streamSw = Stopwatch()..start();
    final media = await _mediaUrl(provider, playback);

    if (media == null) {
      steps.add(ProbeStep(
        stage: ProbeStage.stream,
        outcome: ProbeOutcome.failed,
        detail: 'no playable link came back',
        millis: streamSw.elapsedMilliseconds,
      ));
      return _finish(provider, query, steps, total, from: ProbeStage.playback);
    }

    steps.add(ProbeStep(
      stage: ProbeStage.stream,
      outcome: ProbeOutcome.ok,
      detail: _hostOf(media.url),
      millis: streamSw.elapsedMilliseconds,
    ));

    // --- playback --------------------------------------------------------
    final reachSw = Stopwatch()..start();
    final reach = await _reach(media);
    steps.add(ProbeStep(
      stage: ProbeStage.playback,
      outcome: reach.$1 ? ProbeOutcome.ok : ProbeOutcome.failed,
      detail: reach.$2,
      millis: reachSw.elapsedMilliseconds,
    ));

    return _finish(provider, query, steps, total, from: null);
  }

  // --- stages ------------------------------------------------------------

  Future<ProviderSearchResult?> _searchOnce(ProviderRef ref, String term) async {
    try {
      await for (final r in _engine.search(set: [ref], query: term)) {
        return r;
      }
    } catch (e) {
      debugPrint('$_tag ${ref.id} search threw: $e');
    }
    return null;
  }

  /// The first media URL this source will actually hand over.
  ///
  /// A serial has to go through resolve — the episode list holds refs, not
  /// links, and resolving is exactly the step that breaks when a source starts
  /// refusing datacenter IPs or its extractor goes stale.
  Future<_Media?> _mediaUrl(
    ProviderEntity provider,
    PlaybackEntity playback,
  ) async {
    if (playback.episodes.isNotEmpty) {
      final ep = playback.episodes.first;
      if (ep.mediaRef.isEmpty) return null;
      final resolved = (await _resolve(
        ref: ep.mediaRef,
        provider: provider.id,
      ))
          .getOrNull();
      if (resolved == null) return null;
      final url = resolved.videoSources.isNotEmpty
          ? resolved.videoSources.first.videoUrl
          : resolved.videoUrl;
      if (url.isEmpty) return null;
      return _Media(
        url: url,
        headers: {
          ...resolved.headers,
          if (resolved.videoSources.isNotEmpty)
            ...resolved.videoSources.first.headers,
        },
      );
    }

    final url = playback.videoSources.isNotEmpty
        ? playback.videoSources.first.videoUrl
        : (playback.playerSrc ?? '');
    if (url.isEmpty) return null;
    return _Media(
      url: url,
      headers: {
        ...playback.headers,
        if (playback.videoSources.isNotEmpty)
          ...playback.videoSources.first.headers,
      },
    );
  }

  /// Ask the CDN for the first bytes, with the headers the player would send.
  ///
  /// A ranged GET rather than HEAD: plenty of these CDNs answer HEAD with 405
  /// or with a status that has nothing to do with whether the file plays, and
  /// a probe that reports a working source as broken is worse than none.
  Future<(bool, String)> _reach(_Media media) async {
    try {
      final res = await _dio.get<void>(
        media.url,
        options: Options(
          headers: {...media.headers, 'Range': 'bytes=0-1023'},
          // The shared client attaches the Sozo bearer token to everything it
          // sends. This request goes to a third-party CDN, so the token is
          // dropped the way the rest of the app drops it for off-backend hosts
          // — the cookie jar and the Cloudflare bypass are what make this
          // client worth reusing, not the credential.
          extra: const {'skipAuthInterceptor': true},
          responseType: ResponseType.stream,
          followRedirects: true,
          sendTimeout: _reachTimeout,
          receiveTimeout: _reachTimeout,
          validateStatus: (_) => true,
        ),
      );
      final code = res.statusCode ?? 0;
      // 206 is the honest answer to a range request; 200 means the server
      // ignored the range and would have sent the whole file, which still
      // proves it serves this client.
      if (code == 200 || code == 206) return (true, 'HTTP $code');
      return (false, 'HTTP $code');
    } on DioException catch (e) {
      return (false, _reason(e));
    } catch (e) {
      return (false, e.toString());
    }
  }

  // --- helpers -----------------------------------------------------------

  ProviderProbeResult _finish(
    ProviderEntity provider,
    String query,
    List<ProbeStep> steps,
    Stopwatch total, {
    ProbeStage? from,
  }) {
    if (from != null) {
      // Every stage appears in every result, so a reader compares two sources
      // by reading the same four rows rather than counting how many are there.
      for (final stage in ProbeStage.values) {
        if (stage.index >= from.index) {
          steps.add(ProbeStep(stage: stage, outcome: ProbeOutcome.skipped));
        }
      }
    }
    return ProviderProbeResult(
      providerId: provider.id,
      providerName: provider.name,
      query: query,
      steps: steps,
      millis: total.elapsedMilliseconds,
    );
  }

  static String _reason(DioException e) => switch (e.type) {
        DioExceptionType.connectionTimeout => 'connection timed out',
        DioExceptionType.sendTimeout => 'send timed out',
        DioExceptionType.receiveTimeout => 'receive timed out',
        DioExceptionType.connectionError => 'could not connect',
        DioExceptionType.badCertificate => 'bad certificate',
        DioExceptionType.badResponse => 'HTTP ${e.response?.statusCode ?? '?'}',
        DioExceptionType.cancel => 'cancelled',
        DioExceptionType.unknown => 'no answer',
      };

  @visibleForTesting
  static String hostOf(String url) => _hostOf(url);

  static String _hostOf(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.isEmpty ? 'link' : host;
  }
}

class _Candidate {
  const _Candidate({required this.url, required this.title});
  final String url;
  final String title;
}

class _Media {
  const _Media({required this.url, required this.headers});
  final String url;
  final Map<String, String> headers;
}
