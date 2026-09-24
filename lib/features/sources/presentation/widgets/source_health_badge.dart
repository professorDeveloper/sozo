import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/app_dates.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/search/data/source_health_store.dart';

/// The app's store, or a bare one where DI is not set up (widget tests). Every
/// instance reads the same Hive keys, so the fallback sees the same verdicts.
SourceHealthStore sourceHealth() => getIt.isRegistered<SourceHealthStore>()
    ? getIt<SourceHealthStore>()
    : SourceHealthStore();

const Color _cloudflareColor = Color(0xFFF6A623);

Color _colorOf(RemoteHealth state) =>
    state == RemoteHealth.dead ? AppColors.errorLight : _cloudflareColor;

/// A small 'Down' or 'Cloudflare' pill. Tapping it says why.
class SourceHealthBadge extends StatelessWidget {
  const SourceHealthBadge({
    super.key,
    required this.verdict,
    required this.sourceName,
  });

  final RemoteVerdict verdict;
  final String sourceName;

  @override
  Widget build(BuildContext context) {
    final dead = verdict.state == RemoteHealth.dead;
    final color = _colorOf(verdict.state);
    final label = (dead ? 'sources.health_down' : 'sources.health_cloudflare')
        .tr();
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          showSourceHealthDetails(context, sourceName, verdict);
        },
        child: Padding(
          // A bigger target than the pill itself, without a bigger pill.
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  dead ? Icons.cloud_off_rounded : Icons.shield_outlined,
                  size: 11,
                  color: color,
                ),
                const SizedBox(width: 3),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String healthReasonText(String? reason) {
  const known = {
    'parked',
    'dns',
    'tls',
    'timeout',
    'unreachable',
    'http_5xx',
    'blocked',
    'slow_response',
    'maintainer_down',
    'maintainer_slow',
  };
  return (known.contains(reason)
          ? 'sources.health_reason_$reason'
          : 'sources.health_reason_unknown')
      .tr();
}

Future<void> showSourceHealthDetails(
  BuildContext context,
  String sourceName,
  RemoteVerdict verdict,
) {
  return showAdaptiveModal<void>(
    context: context,
    backgroundColor: AppColors.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _HealthSheet(name: sourceName, verdict: verdict),
  );
}

class _HealthSheet extends StatelessWidget {
  const _HealthSheet({required this.name, required this.verdict});

  final String name;
  final RemoteVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final dead = verdict.state == RemoteHealth.dead;
    final color = _colorOf(verdict.state);
    final checkedAt = verdict.checkedAt;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    dead ? Icons.cloud_off_rounded : Icons.shield_outlined,
                    color: color,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (dead
                                ? 'sources.health_down_title'
                                : 'sources.health_cloudflare_title')
                            .tr(),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'sources.health_reason'.tr(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: AppColors.textHint,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    healthReasonText(verdict.reason),
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (checkedAt != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'sources.health_checked'.tr(
                        args: [AppDates.short(context, checkedAt)],
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              (dead
                      ? 'sources.health_down_body'
                      : 'sources.health_cloudflare_body')
                  .tr(),
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('general.ok'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The 'Hide down sources' switch, shown only when there is something to hide.
class HideDownChip extends StatelessWidget {
  const HideDownChip({
    super.key,
    required this.count,
    required this.hidden,
    required this.onChanged,
  });

  final int count;
  final bool hidden;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      avatar: Icon(
        hidden ? Icons.visibility_off_rounded : Icons.cloud_off_rounded,
        size: 16,
        color: hidden ? AppColors.primary : AppColors.textSecondary,
      ),
      label: Text('sources.hide_down'.tr(args: ['$count'])),
      selected: hidden,
      showCheckmark: false,
      labelStyle: TextStyle(
        fontSize: 12.5,
        color: hidden ? AppColors.textPrimary : AppColors.textSecondary,
        fontWeight: hidden ? FontWeight.w600 : FontWeight.w500,
      ),
      selectedColor: AppColors.primary.withValues(alpha: 0.18),
      backgroundColor: AppColors.card,
      side: BorderSide(
        color: hidden
            ? AppColors.primary.withValues(alpha: 0.5)
            : Colors.transparent,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      visualDensity: VisualDensity.compact,
      onSelected: (v) {
        HapticFeedback.selectionClick();
        onChanged(v);
      },
    );
  }
}
