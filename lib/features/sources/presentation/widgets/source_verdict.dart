import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/sources/data/source_check_store.dart';
import 'package:soplay/features/sources/domain/source_check_service.dart';

String verdictLabel(SourceVerdict v) => switch (v) {
  SourceVerdict.alive => 'sources.v_alive'.tr(),
  SourceVerdict.empty => 'sources.v_empty'.tr(),
  SourceVerdict.blocked => 'sources.v_blocked'.tr(),
  SourceVerdict.outdated => 'sources.v_outdated'.tr(),
  SourceVerdict.failing => 'sources.v_failing'.tr(),
  SourceVerdict.dead => 'sources.v_dead'.tr(),
  SourceVerdict.unknown => 'sources.v_unknown'.tr(),
};

Color verdictColor(SourceVerdict v) => switch (v) {
  SourceVerdict.alive => const Color(0xFF3DDC84),
  SourceVerdict.empty => const Color(0xFF9E9E9E),
  SourceVerdict.blocked => const Color(0xFFFFB300),
  SourceVerdict.outdated => const Color(0xFFB388FF),
  SourceVerdict.failing => const Color(0xFFFF8A50),
  SourceVerdict.dead => const Color(0xFFFF5252),
  SourceVerdict.unknown => const Color(0xFF9E9E9E),
};

/// "3 h ago", for when a verdict was reached.
String checkedAgo(int at) {
  final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(at));
  if (d.inMinutes < 1) return 'sources.just_now'.tr();
  if (d.inHours < 1) return 'sources.min_ago'.tr(args: ['${d.inMinutes}']);
  if (d.inDays < 1) return 'sources.h_ago'.tr(args: ['${d.inHours}']);
  return 'sources.d_ago'.tr(args: ['${d.inDays}']);
}

/// The verdict and what the source said, for the actions sheet.
class VerdictLine extends StatelessWidget {
  const VerdictLine({super.key, required this.id, required this.store});

  final String id;
  final SourceCheckStore store;

  @override
  Widget build(BuildContext context) {
    final check = store.of(id);
    if (check == null) return Text('sources.v_unknown'.tr());
    return Text(
      [
        '${verdictLabel(check.verdict)} · ${checkedAgo(check.at)}',
        if ((check.detail ?? '').isNotEmpty) check.detail!,
      ].join('\n'),
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: verdictColor(check.verdict), fontSize: 12.5),
    );
  }
}

/// How far a check run has got, under the hub's header, with a way to stop.
class CheckProgressStrip extends StatelessWidget {
  const CheckProgressStrip({
    super.key,
    required this.progress,
    required this.onCancel,
  });

  final ValueListenable<SourceCheckProgress?> progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SourceCheckProgress?>(
      valueListenable: progress,
      builder: (_, p, _) {
        if (p == null) return const SizedBox.shrink();
        final bad =
            (p.counts[SourceVerdict.dead] ?? 0) +
            (p.counts[SourceVerdict.failing] ?? 0) +
            (p.counts[SourceVerdict.outdated] ?? 0);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.finished
                          ? 'sources.check_retrying'.tr()
                          : 'sources.checking'.tr(
                              args: ['${p.done}', '${p.total}'],
                            ),
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: p.total == 0 || p.finished
                            ? null
                            : p.done / p.total,
                        minHeight: 4,
                        color: bad > 0
                            ? verdictColor(SourceVerdict.failing)
                            : AppColors.primary,
                        backgroundColor: AppColors.surfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onCancel,
                child: Text('general.cancel'.tr()),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// What a check run found, and the one action it suggests.
class CheckSummarySheet extends StatelessWidget {
  const CheckSummarySheet({
    super.key,
    required this.result,
    required this.bad,
    required this.names,
    required this.store,
    required this.hidingDown,
    required this.onHideDown,
  });

  final SourceCheckProgress result;

  /// Sources the run found not working or needing an update.
  final List<String> bad;
  final Map<String, String> names;
  final SourceCheckStore store;

  /// Whether down sources are already filtered out of the lists.
  final bool hidingDown;
  final VoidCallback onHideDown;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final order = [
      SourceVerdict.alive,
      SourceVerdict.blocked,
      SourceVerdict.empty,
      SourceVerdict.failing,
      SourceVerdict.outdated,
      SourceVerdict.dead,
    ];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'sources.check_done'.tr(),
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              if (r.networkDown)
                Text(
                  'sources.check_network'.tr(),
                  style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final v in order)
                      if ((r.counts[v] ?? 0) > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: verdictColor(v).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${verdictLabel(v)}  ${r.counts[v]}',
                            style: TextStyle(
                              color: verdictColor(v),
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                  ],
                ),
              if (!r.networkDown && bad.isNotEmpty) ...[
                const SizedBox(height: 16),
                Flexible(
                  // Built lazily: a run over a thousand sources can come
                  // back with hundreds of them.
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: bad.length,
                    itemBuilder: (_, i) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(names[bad[i]] ?? bad[i]),
                      subtitle: VerdictLine(id: bad[i], store: store),
                    ),
                  ),
                ),
                if (!hidingDown) ...[
                  const SizedBox(height: 10),
                  Text(
                    'sources.check_bad_hint'.tr(),
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onHideDown,
                      child: Text('sources.check_hide_down'.tr()),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text('general.close'.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Checks one source on request and says what it found — the manual check,
/// for the one source somebody is looking at among hundreds.
class CheckNowButton extends StatefulWidget {
  const CheckNowButton({super.key, required this.id});

  final String id;

  @override
  State<CheckNowButton> createState() => _CheckNowButtonState();
}

class _CheckNowButtonState extends State<CheckNowButton> {
  bool _busy = false;

  SourceCheckService? get _service => getIt.isRegistered<SourceCheckService>()
      ? getIt<SourceCheckService>()
      : null;

  Future<void> _run() async {
    final service = _service;
    if (service == null) return;
    setState(() => _busy = true);
    try {
      await service.check(widget.id);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    if (service == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueListenableBuilder<int>(
          valueListenable: service.store.revision,
          builder: (_, _, _) => service.store.of(widget.id) == null
              ? Text(
                  'sources.never_checked'.tr(),
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                  ),
                )
              : VerdictLine(id: widget.id, store: service.store),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _run,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.health_and_safety_outlined, size: 18),
            label: Text(
              _busy ? 'sources.checking_one'.tr() : 'sources.check_now'.tr(),
            ),
          ),
        ),
      ],
    );
  }
}

/// What this phone knows about one source, and a way to ask again.
Future<void> showSourceCheckSheet(
  BuildContext context, {
  required String id,
  required String name,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            CheckNowButton(id: id),
          ],
        ),
      ),
    ),
  );
}

