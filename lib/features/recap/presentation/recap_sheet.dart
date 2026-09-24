import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';
import 'package:soplay/core/widgets/shimmer_wrapper.dart';
import 'package:soplay/features/recap/data/recap_remote_data_source.dart';
import 'package:soplay/features/recap/domain/recap.dart';

/// "Previously on…": what happened before the episode the viewer is about
/// to start, and nothing after it.
class RecapSheet extends StatefulWidget {
  const RecapSheet({
    super.key,
    required this.request,
    required this.lang,
    required this.source,
  });

  final RecapRequest request;
  final String lang;
  final RecapRemoteDataSource source;

  static Future<void> show(BuildContext context, RecapRequest request) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => RecapSheet(
        request: request,
        lang: context.locale.languageCode,
        source: getIt<RecapRemoteDataSource>(),
      ),
    );
  }

  @override
  State<RecapSheet> createState() => _RecapSheetState();
}

enum _Phase { loading, ready, unavailable, error }

class _RecapSheetState extends State<RecapSheet> {
  _Phase _phase = _Phase.loading;
  Recap? _recap;

  @override
  void initState() {
    super.initState();
    final hit = widget.source.peek(widget.request, lang: widget.lang);
    if (hit != null) {
      _recap = hit;
      _phase = _Phase.ready;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    if (_phase != _Phase.loading) setState(() => _phase = _Phase.loading);
    try {
      final recap = await widget.source.load(widget.request, lang: widget.lang);
      if (!mounted) return;
      setState(() {
        _recap = recap;
        _phase = _Phase.ready;
      });
    } on RecapUnavailable {
      if (mounted) setState(() => _phase = _Phase.unavailable);
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recap = _recap;
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: EdgeInsets.fromLTRB(
                  20,
                  4,
                  20,
                  MediaQuery.paddingOf(context).bottom + 24,
                ),
                children: [
                  _Header(
                    title: recap?.title ?? widget.request.title,
                    upTo: _phase == _Phase.ready ? recap : null,
                  ),
                  const SizedBox(height: 18),
                  ...switch (_phase) {
                    _Phase.loading => [const _LoadingBody()],
                    _Phase.ready => _readyBody(recap!),
                    _Phase.unavailable => [
                      _Notice(
                        icon: Icons.auto_stories_outlined,
                        title: 'recap.unavailable_title'.tr(),
                        body: 'recap.unavailable'.tr(),
                      ),
                    ],
                    _Phase.error => [
                      _Notice(
                        icon: Icons.cloud_off_rounded,
                        title: 'recap.error'.tr(),
                        action: OutlinedButton.icon(
                          onPressed: _load,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            side: BorderSide(color: AppColors.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                kButtonRadius,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text('general.retry'.tr()),
                        ),
                      ),
                    ],
                  },
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _readyBody(Recap recap) {
    final credit = [
      if (recap.attribution != null)
        'recap.source'.tr(args: [recap.attribution!]),
      if (recap.fromModel) 'recap.ai_note'.tr(),
    ].join(' · ');
    return [
      for (final p in recap.paragraphs)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            p,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              height: 1.55,
            ),
          ),
        ),
      const SizedBox(height: 4),
      _SpoilerNote(before: episodeCode(recap.season, recap.episode)),
      if (recap.items.isNotEmpty) ...[
        const SizedBox(height: 22),
        Text(
          'recap.covers'.tr(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        for (final item in recap.items) _CoveredItem(item: item),
      ],
      if (credit.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text(
          credit,
          style: const TextStyle(color: AppColors.textHint, fontSize: 11.5),
        ),
      ],
    ];
  }
}

/// "S2 · E5", or "Ep 5" for absolute numbering.
String episodeCode(int? season, int? episode) {
  if (season != null && episode != null) {
    return 'recap.code_season_episode'.tr(args: ['$season', '$episode']);
  }
  if (episode != null) return 'recap.code_episode'.tr(args: ['$episode']);
  return season == null ? '' : 'recap.season_n'.tr(args: ['$season']);
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.upTo});

  final String title;
  final Recap? upTo;

  @override
  Widget build(BuildContext context) {
    final upTo = this.upTo;
    final last = upTo?.upToEpisode;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.history_edu_rounded,
            color: AppColors.primary,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'recap.previously_on'.tr().toUpperCase(),
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              if (last != null && last > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'recap.up_to'.tr(args: [episodeCode(upTo!.season, last)]),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SpoilerNote extends StatelessWidget {
  const _SpoilerNote({required this.before});

  final String before;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(kButtonRadius),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.verified_user_outlined,
            color: AppColors.success,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'recap.spoiler_safe'.tr(args: [before]),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoveredItem extends StatefulWidget {
  const _CoveredItem({required this.item});

  final RecapItem item;

  @override
  State<_CoveredItem> createState() => _CoveredItemState();
}

class _CoveredItemState extends State<_CoveredItem> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final code = item.isSeason
        ? 'recap.season_n'.tr(args: ['${item.season ?? ''}'])
        : episodeCode(item.season, item.episode);
    final hasOverview = item.overview.isNotEmpty;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: hasOverview ? () => setState(() => _open = !_open) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              constraints: const BoxConstraints(minWidth: 58),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                code,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.name != null)
                    Text(
                      item.name!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (hasOverview) ...[
                    const SizedBox(height: 2),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      alignment: Alignment.topCenter,
                      child: Text(
                        item.overview,
                        maxLines: _open ? null : 2,
                        overflow: _open ? null : TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    Widget bar(double widthFactor) => FractionallySizedBox(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: widthFactor,
      child: Container(
        height: 13,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShimmerWrapper(
          child: Column(
            children: [
              for (final w in const [1.0, 0.94, 0.98, 0.9, 0.6]) bar(w),
              const SizedBox(height: 10),
              for (final w in const [1.0, 0.96, 0.7]) bar(w),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'recap.loading'.tr(),
          style: const TextStyle(color: AppColors.textHint, fontSize: 12.5),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 40),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(
              body!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}
