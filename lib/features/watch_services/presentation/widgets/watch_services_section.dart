import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/features/watch_services/domain/entities/watch_service_entity.dart';
import 'package:soplay/features/watch_services/domain/watch_region.dart';
import 'package:soplay/features/watch_services/presentation/bloc/watch_services/watch_services_bloc.dart';
import 'package:soplay/features/watch_services/presentation/pages/watch_service_browse_page.dart';
import 'package:soplay/features/watch_services/presentation/widgets/watch_service_tile.dart';

/// The streaming services available where the viewer is.
///
/// Independent of the selected source on purpose, which is unusual for a Home
/// band: what a country's services carry is a fact about the world, not about
/// which extension happens to be current, and it is the one shelf that still
/// works when every installed source is down.
class WatchServicesSection extends StatelessWidget {
  const WatchServicesSection({super.key});

  /// How many marks before the header takes over.
  ///
  /// Twelve fills the rail on a tablet and stops before the long tail of
  /// regional services nobody recognises by logo — a country can list three
  /// hundred. They are ordered by TMDB's own per-region priority, so these
  /// twelve are the ones people there actually have.
  static const int _limit = 12;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<WatchServicesBloc>.value(
      value: getIt<WatchServicesBloc>()..add(const WatchServicesLoad()),
      child: BlocBuilder<WatchServicesBloc, WatchServicesState>(
        builder: (context, state) {
          // A rail nobody asked for should not grow an error strip on a screen
          // full of other things. The place a failure is SHOWN is the services
          // page, where somebody went looking.
          if (state.status == WatchServicesStatus.error) {
            return const SizedBox.shrink();
          }
          if (state.status == WatchServicesStatus.loaded &&
              !state.hasServices) {
            return const SizedBox.shrink();
          }
          final loading = !state.hasServices;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(context, state),
                SizedBox(
                  height: WatchServiceTile.railHeight(context),
                  child: loading
                      ? _skeleton(context)
                      : _rail(context, state.services, state.region),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context, WatchServicesState state) =>
      HomeSectionTapTarget(
        onTap: () => context.push('/watch-services'),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(17, 18, 20, 14),
          child: Row(
            children: [
              const Icon(
                Icons.subscriptions_rounded,
                color: AppColors.textSecondary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'watch.services_title'.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // The whole rail is a claim about a country, and the flag in the
              // header is what stops "why is Netflix showing me Brazilian
              // films" from being a mystery. Not a second way into the picker —
              // the header is one tap target, and the picker is one screen in.
              _RegionBadge(code: state.region),
              const Spacer(),
              Text(
                'home.view_all'.tr(),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
                size: 18,
              ),
            ],
          ),
        ),
      );

  Widget _rail(
    BuildContext context,
    List<WatchServiceEntity> services,
    String region,
  ) {
    final shown = services.take(_limit).toList();
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      // `isDesktopPlatform` is FALSE on a television, so the usual
      // `isDesktopPlatform ? none : hardEdge` clips the focus ring and the
      // focus scale at the rail's edge on exactly the platform that has them.
      clipBehavior: (isTvPlatform || isDesktopPlatform)
          ? Clip.none
          : Clip.hardEdge,
      itemCount: shown.length,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (context, i) => WatchServiceTile(
        service: shown[i],
        onTap: (s) => openWatchService(context, s, region: region),
      ),
    );
  }

  /// A shimmering rail rather than nothing.
  ///
  /// Live TV renders nothing until it has channels; this reserves its space,
  /// because the band belongs to a REGION the viewer set — it was opted into,
  /// so promising it is honest, and it stops Home jumping under a thumb
  /// mid-scroll.
  Widget _skeleton(BuildContext context) {
    final size = WatchServiceTile.sizeFor();
    return ShimmerWrapper(
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: 6,
        itemBuilder: (_, _) => Padding(
          padding: const EdgeInsetsDirectional.only(end: 10),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }
}

class _RegionBadge extends StatelessWidget {
  const _RegionBadge({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    if (code.isEmpty) return const SizedBox.shrink();
    final flag = regionFlag(code);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (flag.isNotEmpty && !isDesktopPlatform) ...[
            Text(flag, style: const TextStyle(fontSize: 11)),
            const SizedBox(width: 4),
          ],
          Text(
            code,
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
