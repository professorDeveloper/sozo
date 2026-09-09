import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';
import 'package:soplay/features/detail/domain/services/alternate_source_service.dart';

/// "This source is down — here is who else has it."
///
/// Opened from two places: the player's error screen, where a source has just
/// failed, and the detail page, where someone would rather not find out the
/// hard way. Both want the same thing — this title, playing, somewhere else.
///
/// Results stream in per provider rather than arriving as one list. Someone
/// already waiting on a failure is better served by the first working source
/// after two seconds than a complete list after fifteen; sources that answer
/// late simply appear below the ones that answered early.
///
/// Returns the [PlayerArgs] for the source the viewer picked, or null.
class AlternateSourceSheet extends StatefulWidget {
  const AlternateSourceSheet._({
    required this.title,
    required this.provider,
    required this.category,
    required this.episodeNumber,
    required this.headers,
    this.resumeAt = Duration.zero,
  });

  final String title;
  final String provider;
  final String category;
  final int? episodeNumber;
  final Map<String, String> headers;

  /// Where the viewer is now, carried onto the source they pick.
  ///
  /// Zero when the sheet opens from a playback failure — there is nothing to
  /// resume to. Non-zero when they chose to switch mid-episode, which is the
  /// case that must not restart it.
  final Duration resumeAt;

  static Future<PlayerArgs?> show(
    BuildContext context, {
    required String title,
    required String provider,
    required String category,
    required int? episodeNumber,
    required Map<String, String> headers,
    Duration resumeAt = Duration.zero,
  }) {
    return showAdaptiveModal<PlayerArgs>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => AlternateSourceSheet._(
        title: title,
        provider: provider,
        category: category,
        episodeNumber: episodeNumber,
        headers: headers,
        resumeAt: resumeAt,
      ),
    );
  }

  @override
  State<AlternateSourceSheet> createState() => _AlternateSourceSheetState();
}

class _AlternateSourceSheetState extends State<AlternateSourceSheet> {
  /// Torrent streaming is Android-only — the engine is a native Android
  /// library. Hidden elsewhere rather than shown and failing.
  static bool get _torrentsAvailable => !kIsWeb && Platform.isAndroid;

  final List<AlternateSource> _found = [];
  StreamSubscription<AlternateSource>? _sub;
  bool _searching = true;

  /// Set while an entry is being turned into PlayerArgs, so the row can show a
  /// spinner and the rest of the list stops accepting taps. Fetching an episode
  /// list is a network call, and without this a second tap starts a second one.
  String? _preparing;

  @override
  void initState() {
    super.initState();
    _sub = getIt<AlternateSourceService>()
        .find(
          title: widget.title,
          excludeProvider: widget.provider,
          category: widget.category,
        )
        .listen(
          (s) {
            if (!mounted) return;
            setState(() {
              _found.add(s);
              // Best match first. The list grows while it is on screen, so this
              // is a re-sort rather than a sorted insert — it is a handful of
              // entries and the alternative is watching rows jump around less
              // predictably than they do now.
              _found.sort((a, b) => b.score.compareTo(a.score));
            });
          },
          onDone: () {
            if (mounted) setState(() => _searching = false);
          },
          onError: (_) {
            if (mounted) setState(() => _searching = false);
          },
        );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _pick(AlternateSource source) async {
    if (_preparing != null) return;
    setState(() => _preparing = source.provider.id);
    final args = await getIt<AlternateSourceService>().buildArgs(
      source: source,
      episodeNumber: widget.episodeNumber,
      headers: widget.headers,
      resumeAt: widget.resumeAt,
    );
    if (!mounted) return;
    if (args == null) {
      setState(() => _preparing = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.episodeNumber != null
                // The common failure, and worth naming precisely: the source
                // has the show but not this episode number.
                ? 'player.alt_no_episode'.tr(args: ['${widget.episodeNumber}'])
                : 'player.alt_failed'.tr(),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    Navigator.of(context).pop(args);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.swap_horiz_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'player.alt_sources'.tr(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (_searching)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white54,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          Flexible(
            child: _found.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _searching
                              ? 'player.alt_searching'.tr()
                              : 'player.alt_none'.tr(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                          ),
                        ),
                        // Only once the search is over, and only when it found
                        // nothing. Cross-search casts a wider net — every
                        // category, no title matching — so it is the right next
                        // step for someone this sheet could not help, and a
                        // dead end is the wrong thing to leave them with.
                        if (!_searching) ...[
                          const SizedBox(height: 14),
                          TextButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              context.push('/cross-search', extra: widget.title);
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white70,
                            ),
                            icon: const Icon(Icons.travel_explore_rounded, size: 18),
                            label: Text('player.alt_search_all'.tr()),
                          ),
                          // The last resort, and this is the moment for it: a
                          // source just failed and none of the others has the
                          // title either. Offering torrents earlier would push
                          // people onto BitTorrent for something that streams
                          // fine; offering nothing here leaves them at a dead
                          // end.
                          if (_torrentsAvailable)
                            TextButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                                context.push('/torrents', extra: widget.title);
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white70,
                              ),
                              icon: const Icon(Icons.hub_rounded, size: 18),
                              label: Text('search.try_torrents'.tr()),
                            ),
                        ],
                      ],
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _found.length,
                    itemBuilder: (_, i) {
                      final s = _found[i];
                      final busy = _preparing == s.provider.id;
                      return ListTile(
                        dense: true,
                        enabled: _preparing == null,
                        onTap: () => _pick(s),
                        leading: busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white54,
                                ),
                              )
                            : const Icon(
                                Icons.play_circle_outline_rounded,
                                color: Colors.white70,
                                size: 22,
                              ),
                        title: Text(
                          s.provider.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        // The source's own title for the show, not ours. Two
                        // catalogues spell the same series differently, and
                        // seeing which one this source means is how the viewer
                        // tells a real match from a near miss before committing.
                        subtitle: Text(
                          s.item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
