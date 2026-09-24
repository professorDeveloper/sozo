import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/network/image_headers.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/services/alternate_source_service.dart';
import 'package:soplay/features/detail/domain/usecases/get_episodes_usecase.dart';
import 'package:soplay/features/download/domain/entities/downloaded_title.dart';
import 'package:soplay/features/download/domain/usecases/relink_downloads_usecase.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_state.dart';

/// Picks another source for a downloaded title and moves its downloads there,
/// keeping the files and the progress.
class RelinkSourceSheet extends StatefulWidget {
  const RelinkSourceSheet._({required this.title});

  final DownloadedTitle title;

  static Future<RelinkOutcome?> show(
    BuildContext context, {
    required DownloadedTitle title,
  }) => showAdaptiveModal<RelinkOutcome>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => RelinkSourceSheet._(title: title),
  );

  @override
  State<RelinkSourceSheet> createState() => _RelinkSourceSheetState();
}

class _RelinkSourceSheetState extends State<RelinkSourceSheet> {
  /// A long run is fetched a page at a time; past this many pages the rest
  /// stay unmatched rather than the sheet spinning for a minute.
  static const int _maxPages = 30;

  final List<AlternateSource> _found = [];
  StreamSubscription<AlternateSource>? _sub;
  bool _searching = true;
  AlternateSearchOutcome? _outcome;
  String? _preparing;
  ({String provider, String message})? _failed;

  @override
  void initState() {
    super.initState();
    final title = widget.title;
    final candidates = _candidates();
    _sub = getIt<AlternateSourceService>()
        .find(
          title: title.title,
          excludeProvider: title.provider,
          titleProvider: title.provider,
          candidates: candidates.isEmpty ? null : candidates,
          onOutcome: (o) {
            if (mounted) setState(() => _outcome = o);
          },
        )
        .listen(
          (s) {
            if (!mounted) return;
            setState(() {
              _found
                ..add(s)
                ..sort((a, b) => b.score.compareTo(a.score));
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

  List<ProviderEntity> _candidates() {
    try {
      final state = context.read<ProviderBloc>().state;
      return state is ProviderLoaded ? state.usableProviders : const [];
    } catch (_) {
      return const [];
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _emptyMessage() {
    final outcome = _outcome;
    if (outcome == null) return 'player.alt_no_answer'.tr();
    if (outcome.unavailable) return 'player.alt_unavailable'.tr();
    if (outcome.asked == 0) return 'player.alt_none_asked'.tr();
    if (outcome.failed >= outcome.asked) return 'player.alt_all_failed'.tr();
    if (outcome.failed > 0) {
      return 'player.alt_some_failed'.tr(args: ['${outcome.failed}']);
    }
    return 'downloads.relink_none'.tr();
  }

  Future<List<EpisodeEntity>?> _episodesOf(AlternateSource source) async {
    final episodes = getIt<GetEpisodesUseCase>();
    final all = <EpisodeEntity>[];
    var page = 1;
    var totalPages = 1;
    do {
      final result = await episodes(
        source.item.url,
        provider: source.provider.id,
        page: page,
      );
      final value = result.getOrNull();
      if (value == null) return page == 1 ? null : all;
      all.addAll(value.episodes);
      totalPages = value.totalPages;
      page++;
    } while (page <= totalPages && page <= _maxPages);
    return all;
  }

  Future<void> _pick(AlternateSource source) async {
    if (_preparing != null) return;
    final providerName = source.provider.name;
    setState(() {
      _preparing = source.provider.id;
      _failed = null;
    });
    void fail(String message) {
      if (!mounted) return;
      setState(() {
        _preparing = null;
        _failed = (provider: source.provider.id, message: message);
      });
    }

    final episodes = await _episodesOf(source);
    if (!mounted) return;
    if (episodes == null && !widget.title.isMovie) {
      fail('downloads.relink_failed'.tr(args: [providerName]));
      return;
    }
    final relink = getIt<RelinkDownloadsUseCase>();
    final plan = relink.plan(
      widget.title.key,
      provider: source.provider.id,
      contentUrl: source.item.url,
      episodes: episodes ?? const [],
    );
    if (plan.moves.isEmpty) {
      fail('downloads.relink_no_match'.tr(args: [providerName]));
      return;
    }
    final confirmed = await _confirm(
      providerName: providerName,
      matched: plan.moves.length,
      total: plan.total,
    );
    if (!mounted) return;
    if (confirmed != true) {
      setState(() => _preparing = null);
      return;
    }
    final outcome = await relink(
      plan,
      providerName: providerName,
      episodes: episodes ?? const [],
    );
    if (!mounted) return;
    if (outcome.moved == 0) {
      fail('downloads.relink_busy'.tr());
      return;
    }
    Navigator.of(context).pop(outcome);
  }

  Future<bool?> _confirm({
    required String providerName,
    required int matched,
    required int total,
  }) => showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        'downloads.relink_confirm_title'.tr(args: [providerName]),
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 17),
      ),
      content: Text(
        [
          'downloads.relink_confirm_body'.tr(
            namedArgs: {'matched': '$matched', 'total': '$total'},
          ),
          if (total > matched)
            'downloads.relink_confirm_left'.tr(args: ['${total - matched}']),
        ].join('\n\n'),
        style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(
            'general.cancel'.tr(),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text('downloads.relink_action'.tr()),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.swap_horiz_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'downloads.relink'.tr(),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (_searching)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(46, 0, 16, 12),
              child: Text(
                'downloads.relink_desc'.tr(),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ),
            Divider(color: AppColors.divider, height: 1),
            Flexible(
              child: _found.isEmpty
                  ? _EmptyBlock(
                      searching: _searching,
                      message: _searching
                          ? 'downloads.relink_searching'.tr(
                              args: [widget.title.title],
                            )
                          : _emptyMessage(),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: _found.length,
                      separatorBuilder: (_, _) => Divider(
                        color: AppColors.divider,
                        height: 1,
                        indent: 84,
                      ),
                      itemBuilder: (_, i) {
                        final source = _found[i];
                        final failed = _failed?.provider == source.provider.id
                            ? _failed!.message
                            : null;
                        return _SourceRow(
                          source: source,
                          busy: _preparing == source.provider.id,
                          enabled: _preparing == null,
                          failure: failed,
                          onTap: () => _pick(source),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({required this.searching, required this.message});

  final bool searching;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!searching)
            const Icon(
              Icons.travel_explore_rounded,
              color: AppColors.textHint,
              size: 36,
            ),
          if (!searching) const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.source,
    required this.busy,
    required this.enabled,
    required this.onTap,
    this.failure,
  });

  final AlternateSource source;
  final bool busy;
  final bool enabled;
  final String? failure;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final poster = source.item.thumbnail;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 52,
                height: 74,
                child: ColoredBox(
                  color: AppColors.card,
                  child: poster == null || poster.isEmpty
                      ? const Icon(
                          Icons.image_not_supported_outlined,
                          color: AppColors.textHint,
                          size: 20,
                        )
                      : CachedNetworkImage(
                          imageUrl: poster,
                          httpHeaders: posterImageHeaders(poster),
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => const Icon(
                            Icons.broken_image_outlined,
                            color: AppColors.textHint,
                            size: 20,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.provider.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    source.item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                  if (!source.isTrustworthy) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.help_outline_rounded,
                          size: 14,
                          color: AppColors.textHint,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'downloads.relink_guess'.tr(),
                            style: const TextStyle(
                              color: AppColors.textHint,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (failure != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      failure!,
                      style: const TextStyle(
                        color: AppColors.errorLight,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 22),
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textSecondary,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
