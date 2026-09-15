import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/anilist/data/anilist_api.dart';
import 'package:soplay/features/anilist/data/anilist_link_store.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_link_sheet.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_logo.dart';
import 'package:soplay/features/detail/domain/entities/detail_entity.dart';
import 'package:soplay/features/mal/data/mal_link_store.dart';
import 'package:soplay/features/mal/data/mal_service.dart';
import 'package:soplay/features/mal/domain/entities/mal_entities.dart';
import 'package:soplay/features/mal/presentation/widgets/mal_brand.dart';
import 'package:soplay/features/mal/presentation/widgets/mal_link_sheet.dart';

/// Where you are on this title, on the tracker you use — and the two buttons
/// that move it.
///
/// "Track on AniList" and "Track on MyAnimeList" were two rows in the overflow
/// menu that opened a sheet each. Neither said whether the title was tracked,
/// let alone how far along it was; that lived on the tracker's site. This is
/// one row per connected tracker, on the page, with the real number on it —
/// "Watching 5/12" — and − + to move it without leaving.
///
/// Shown only for a tracker that is connected. A title the tracker does not
/// know yet (no link) offers to link it, through the same sheet as before.
class TrackingRow extends StatefulWidget {
  const TrackingRow({super.key, required this.detail});

  final DetailEntity detail;

  @override
  State<TrackingRow> createState() => _TrackingRowState();
}

class _TrackingRowState extends State<TrackingRow> {
  @override
  Widget build(BuildContext context) {
    final anilist = getIt<AnilistService>();
    final mal = getIt<MalService>();
    if (!anilist.isConnected && !mal.isConnected) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (anilist.isConnected) _AnilistLine(detail: widget.detail),
        if (mal.isConnected) ...[
          if (anilist.isConnected) const SizedBox(height: 8),
          _MalLine(detail: widget.detail),
        ],
      ],
    );
  }
}

class _AnilistLine extends StatefulWidget {
  const _AnilistLine({required this.detail});

  final DetailEntity detail;

  @override
  State<_AnilistLine> createState() => _AnilistLineState();
}

class _AnilistLineState extends State<_AnilistLine> {
  AnilistEntryState? _state;
  bool _busy = false;
  bool _failed = false;

  int? get _mediaId =>
      widget.detail.record?.anilistId ??
      getIt<AnilistLinkStore>().mediaIdFor(
        widget.detail.provider,
        widget.detail.contentUrl,
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = _mediaId;
    final token = getIt<AnilistService>().token;
    if (id == null || token == null) return;
    try {
      final s = await getIt<AnilistService>().api.entryState(
        token: token,
        mediaId: id,
      );
      if (mounted) setState(() => _state = s);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _move(int delta) async {
    final id = _mediaId;
    final token = getIt<AnilistService>().token;
    final s = _state;
    if (id == null || token == null || s == null || _busy) return;
    final next = (s.progress + delta).clamp(0, s.totalEpisodes ?? 9999);
    if (next == s.progress) return;
    // Painted before the request: the number moves under the finger, and a
    // failed write puts it back.
    setState(() {
      _busy = true;
      _state = AnilistEntryState(
        onList: true,
        progress: next,
        status: s.status,
        totalEpisodes: s.totalEpisodes,
      );
    });
    try {
      final total = s.totalEpisodes;
      final saved = await getIt<AnilistService>().api.saveProgress(
        token: token,
        mediaId: id,
        progress: next,
        status: total != null && next >= total
            ? AnilistStatus.completed.value
            : (s.status == null || s.status == AnilistStatus.planning.value
                  ? AnilistStatus.current.value
                  : null),
      );
      if (mounted) {
        setState(
          () => _state = AnilistEntryState(
            onList: true,
            progress: saved.progress,
            status: saved.status,
            totalEpisodes: total,
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _state = s);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final id = _mediaId;
    final token = getIt<AnilistService>().token;
    if (id == null || token == null || _busy) return;
    setState(() => _busy = true);
    try {
      await getIt<AnilistService>().api.addToList(
        token: token,
        mediaId: id,
        status: AnilistStatus.current,
      );
      await _load();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _link() async {
    await AnilistLinkSheet.show(
      context,
      provider: widget.detail.provider,
      contentUrl: widget.detail.contentUrl,
      title: widget.detail.title,
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    final linked = _mediaId != null;
    return _TrackerLine(
      logo: const AnilistLogo(size: 22, radius: 6),
      accent: kAnilistBlue,
      name: 'AniList',
      status: !linked
          ? null
          : s == null
          ? (_failed ? '—' : '…')
          : !s.onList
          ? 'detail.not_on_list'.tr()
          : _statusLabel(s.status),
      progress: s != null && s.onList ? s.progress : null,
      total: s?.totalEpisodes,
      busy: _busy,
      onLess: s != null && s.onList && s.progress > 0 ? () => _move(-1) : null,
      onMore:
          s != null &&
              s.onList &&
              (s.totalEpisodes == null || s.progress < s.totalEpisodes!)
          ? () => _move(1)
          : null,
      onTap: !linked ? _link : (s != null && !s.onList ? _add : _link),
      action: !linked
          ? 'detail.anilist_track'.tr()
          : (s != null && !s.onList ? 'detail.add_to_list'.tr() : null),
    );
  }

  static String _statusLabel(String? raw) {
    for (final st in AnilistStatus.values) {
      if (st.value == raw) return st.labelKey.tr();
    }
    return raw ?? '';
  }
}

class _MalLine extends StatefulWidget {
  const _MalLine({required this.detail});

  final DetailEntity detail;

  @override
  State<_MalLine> createState() => _MalLineState();
}

class _MalLineState extends State<_MalLine> {
  MalEntryState? _state;
  bool _busy = false;
  bool _failed = false;

  int? get _animeId =>
      widget.detail.record?.malId ??
      getIt<MalLinkStore>().mediaIdFor(
        widget.detail.provider,
        widget.detail.contentUrl,
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = _animeId;
    final token = getIt<MalService>().token;
    if (id == null || token == null) return;
    try {
      final s = await getIt<MalService>().api.entryState(
        token: token,
        animeId: id,
      );
      if (mounted) setState(() => _state = s);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _move(int delta) async {
    final id = _animeId;
    final token = getIt<MalService>().token;
    final s = _state;
    if (id == null || token == null || s == null || _busy) return;
    final next = (s.watchedEpisodes + delta).clamp(0, s.totalEpisodes ?? 9999);
    if (next == s.watchedEpisodes) return;
    setState(() {
      _busy = true;
      _state = MalEntryState(
        watchedEpisodes: next,
        status: s.status ?? MalStatus.watching,
        totalEpisodes: s.totalEpisodes,
      );
    });
    try {
      final total = s.totalEpisodes;
      final saved = await getIt<MalService>().api.updateProgress(
        token: token,
        animeId: id,
        episodes: next,
        status: total != null && next >= total
            ? MalStatus.completed
            : (s.status == null || s.status == MalStatus.planToWatch
                  ? MalStatus.watching
                  : null),
      );
      // The update answers with the entry, not the anime, so the episode
      // total is not in it; keep the one already known or "5/14" turns into
      // "5" the moment it is touched.
      if (mounted) {
        setState(
          () => _state = MalEntryState(
            watchedEpisodes: saved.watchedEpisodes,
            status: saved.status,
            totalEpisodes: saved.totalEpisodes ?? total,
            isRewatching: saved.isRewatching,
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _state = s);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _link() async {
    await MalLinkSheet.show(
      context,
      provider: widget.detail.provider,
      contentUrl: widget.detail.contentUrl,
      title: widget.detail.title,
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    final linked = _animeId != null;
    final onList = s != null && s.status != null;
    return _TrackerLine(
      logo: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: kMalBlue,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: const Text(
          'MAL',
          style: TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      accent: kMalBlue,
      name: 'MyAnimeList',
      status: !linked
          ? null
          : s == null
          ? (_failed ? '—' : '…')
          : !onList
          ? 'detail.not_on_list'.tr()
          : _statusLabel(s.status!),
      progress: onList ? s.watchedEpisodes : null,
      total: s?.totalEpisodes,
      busy: _busy,
      onLess: onList && s.watchedEpisodes > 0 ? () => _move(-1) : null,
      onMore:
          onList &&
              (s.totalEpisodes == null || s.watchedEpisodes < s.totalEpisodes!)
          ? () => _move(1)
          : null,
      onTap: !linked ? _link : (s != null && !onList ? () => _move(1) : _link),
      action: !linked
          ? 'mal.track'.tr()
          : (s != null && !onList ? 'detail.add_to_list'.tr() : null),
    );
  }

  static String _statusLabel(String raw) => switch (raw) {
    MalStatus.watching => 'anilist.status_current'.tr(),
    MalStatus.completed => 'anilist.status_completed'.tr(),
    MalStatus.onHold => 'anilist.status_paused'.tr(),
    MalStatus.dropped => 'anilist.status_dropped'.tr(),
    MalStatus.planToWatch => 'anilist.status_planning'.tr(),
    _ => raw,
  };
}

/// One tracker, one line: logo, name, status, progress, − +.
class _TrackerLine extends StatelessWidget {
  const _TrackerLine({
    required this.logo,
    required this.accent,
    required this.name,
    required this.status,
    required this.progress,
    required this.total,
    required this.busy,
    required this.onLess,
    required this.onMore,
    required this.onTap,
    required this.action,
  });

  final Widget logo;
  final Color accent;
  final String name;

  /// Null when the title is not linked on this tracker yet.
  final String? status;
  final int? progress;
  final int? total;
  final bool busy;
  final VoidCallback? onLess;
  final VoidCallback? onMore;
  final VoidCallback onTap;

  /// A verb to show instead of the counter: "Track on AniList", "Add to
  /// list". Null when the counter is the content.
  final String? action;

  @override
  Widget build(BuildContext context) {
    final showsCounter = progress != null;
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 6, 6),
          child: Row(
            children: [
              logo,
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: const TextStyle(fontSize: 13),
                    children: [
                      TextSpan(
                        text: name,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (status != null)
                        TextSpan(
                          text: '  ·  $status',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (action != null)
                Text(
                  action!,
                  style: TextStyle(
                    color: accent,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                )
              else if (showsCounter) ...[
                _Step(icon: Icons.remove_rounded, onTap: busy ? null : onLess),
                SizedBox(
                  width: total != null ? 52 : 34,
                  child: Text(
                    total != null ? '$progress/$total' : '$progress',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                _Step(icon: Icons.add_rounded, onTap: busy ? null : onMore),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: EdgeInsets.zero,
      color: AppColors.textPrimary,
      disabledColor: AppColors.textHint,
    );
  }
}
