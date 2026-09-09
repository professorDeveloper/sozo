import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/cloudflare/cloudflare_solver.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_bloc.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_event.dart';
import 'package:soplay/features/home/presentation/widgets/home_banner.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';

class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    // No top bar here — HomePage mounts it once above this subtree, so the
    // Loading -> Loaded flip never re-mounts it (and never re-fires the
    // notifications indicator's unread-count fetch).
    return ShimmerWrapper(
      child: CustomScrollView(
        physics: const NeverScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: HomeBannerSkeleton(topPadding: topPad)),
          // Geometry mirrors the loaded sections exactly (see MovieSection and
          // _GenreSection); when it did not, every rail nudged sideways and
          // downwards the moment the data landed.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(17, 18, 16, 14),
                    child: HomeSkeletonBox(width: 80, height: 19, radius: 4),
                  ),
                  SizedBox(
                    height: 72,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: 6,
                      itemBuilder: (_, _) => const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: HomeSkeletonBox(
                          width: 110,
                          height: 72,
                          radius: 10,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (int i = 0; i < 3; i++) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(17, 18, 20, 14),
                child: Row(
                  children: [
                    HomeSkeletonBox(
                      width: 100 + (i * 24).toDouble(),
                      height: 19,
                      radius: 4,
                    ),
                    const Spacer(),
                    const HomeSkeletonBox(width: 22, height: 19, radius: 4),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: SizedBox(
                  height: 195,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: 6,
                    itemBuilder: (_, _) => const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: _SkeletonCard(),
                    ),
                  ),
                ),
              ),
            ),
          ],
          SliverToBoxAdapter(
            child: SizedBox(
              height: MediaQuery.paddingOf(context).bottom + 88,
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    // Two caption lines, matching _MovieCard — a third line here made the
    // skeleton poster ~13px shorter than the real one.
    return const SizedBox(
      width: 118,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: HomeSkeletonBox(
                width: double.infinity,
                height: double.infinity,
                radius: 10,
              ),
            ),
            SizedBox(height: 6),
            FixedTextLines(
              fontSize: 11.5,
              lineHeight: 1.25,
              child: HomeSkeletonBox(width: 90, height: 11, radius: 3),
            ),
            FixedTextLines(
              fontSize: 10,
              lineHeight: 1.3,
              child: HomeSkeletonBox(width: 40, height: 10, radius: 3),
            ),
          ],
        ),
      ),
    );
  }
}

/// The catalogue failed, said inline above the rows that still work.
///
/// Same words and the same two buttons as [HomeErrorView] — including the
/// Cloudflare branch, so the decision about when to offer a solve lives in one
/// place — but as a band rather than a full screen. The full-screen view is
/// still right when there is genuinely nothing else to show; this is for when
/// Continue Watching and the downloads are sitting right underneath.
class HomeErrorStrip extends StatelessWidget {
  const HomeErrorStrip({super.key, this.message});

  final String? message;

  Future<void> _solveCloudflare(BuildContext context) async {
    final bloc = context.read<HomeBloc>();
    final provider = getIt<HiveService>().getCurrentProvider();
    final ok = await requestCloudflareSolve(context, provider);
    if (ok) bloc.add(HomeLoad());
  }

  @override
  Widget build(BuildContext context) {
    final showCloudflare = isCloudflareError(message);
    final detail = message?.trim();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.wifi_off_rounded,
                  color: AppColors.textSecondary, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'errors.network'.tr(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => context.read<HomeBloc>().add(HomeLoad()),
                child: Text('general.retry'.tr()),
              ),
            ],
          ),
          // The real diagnostic, for the same reason the full view keeps it: a
          // native extension failure is not the same thing as being offline,
          // and the difference is only visible here.
          if (!showCloudflare && (detail?.isNotEmpty ?? false))
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 2),
              child: SelectableText(
                detail!,
                maxLines: 2,
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ),
          if (showCloudflare)
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 6),
              child: OutlinedButton.icon(
                onPressed: () => _solveCloudflare(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: BorderSide(color: AppColors.border),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.shield_outlined, size: 16),
                label: Text('cloudflare.solve'.tr()),
              ),
            ),
        ],
      ),
    );
  }
}

class HomeErrorView extends StatelessWidget {
  const HomeErrorView({super.key, this.message});

  final String? message;

  Future<void> _solveCloudflare(BuildContext context) async {
    final bloc = context.read<HomeBloc>();
    final provider = getIt<HiveService>().getCurrentProvider();
    final ok = await requestCloudflareSolve(context, provider);
    if (ok) bloc.add(HomeLoad());
  }

  @override
  Widget build(BuildContext context) {
    final showCloudflare = isCloudflareError(message);
    // Scrollable: with a long diagnostic and the extra Cloudflare button this
    // column is taller than a short phone in landscape.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                color: AppColors.textSecondary,
                size: 32,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'errors.network'.tr(),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'general.try_again'.tr(),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.35,
              ),
              textAlign: TextAlign.center,
            ),
            // The actual reason, when there is one and it isn't the Cloudflare
            // case (which already has its own button and explanation).
            //
            // Native extension failures arrive here as real diagnostics —
            // "AbstractMethodError", "NoClassDefFoundError: <symbol>",
            // "source unavailable" — and every one of them used to be dropped in
            // favour of a generic "network error". That made an extension
            // problem indistinguishable from being offline, for us as much as
            // for the user. Selectable so it can be copied into a bug report.
            if (!showCloudflare && (message?.trim().isNotEmpty ?? false)) ...[
              const SizedBox(height: 10),
              SelectableText(
                message!.trim(),
                maxLines: 4,
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 11,
                  height: 1.35,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: 156,
              height: 44,
              child: ElevatedButton(
                onPressed: () => context.read<HomeBloc>().add(HomeLoad()),
                child: Text('general.retry'.tr()),
              ),
            ),
            if (showCloudflare) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: 200,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () => _solveCloudflare(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: BorderSide(color: AppColors.border),
                  ),
                  icon: const Icon(Icons.shield_outlined, size: 18),
                  label: Text('cloudflare.solve'.tr()),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shown when the feed loaded successfully but carries nothing at all — no
/// hero, no history, no genres, no sections. That state used to render a bare
/// black screen under the top bar, which is indistinguishable from a hang.
class HomeEmptyView extends StatelessWidget {
  const HomeEmptyView({super.key, required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: const Icon(
                Icons.movie_filter_outlined,
                color: AppColors.textSecondary,
                size: 32,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'home.empty_title'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'home.empty_subtitle'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 156,
              height: 44,
              child: ElevatedButton(
                onPressed: onRefresh,
                child: Text('general.retry'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
