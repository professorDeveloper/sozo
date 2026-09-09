import 'package:flutter/material.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/features/home/domain/catalogue_status.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_bloc.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_event.dart';
import 'package:soplay/features/home/presentation/widgets/backend_outage_banner.dart';
import 'package:soplay/features/home/presentation/widgets/home_content.dart';
import 'package:soplay/features/home/presentation/widgets/home_state_views.dart';
import 'package:soplay/features/home/presentation/widgets/home_top_bar.dart';

import '../bloc/home/home_state.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// Owned HERE, not by [HomeContent], because the top bar now lives outside
  /// the BlocBuilder and outlives every body swap. [HomeContent] only writes
  /// its scroll progress into it.
  final ValueNotifier<double> _blurProgress = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    // Home rebuilds the moment the customizer is saved, not on its next
    // visit: the sheet closes onto this screen and a stale order would read as
    // the change not having taken.
    getIt<HiveService>().homeRailsChanged.addListener(_onRailsChanged);
    context.read<HomeBloc>().add(HomeLoad());
  }

  void _onRailsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    getIt<HiveService>().homeRailsChanged.removeListener(_onRailsChanged);
    _blurProgress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The top bar is a SIBLING of the BlocBuilder, never inside it. It used to
    // be built separately by HomeSkeleton and by HomeContent, so every
    // HomeLoading -> HomeLoaded flip of the app-level HomeBloc tore the bar
    // down and built a new one — re-running _NotificationsIndicator.initState,
    // i.e. one extra GET /notifications/unread-count per transition. Mounted
    // once here, it is only ever updated.
    return BlocListener<HomeBloc, HomeState>(
      // Leaving HomeLoaded destroys the scroll view the blur came from, so drop
      // it — otherwise the bar stays frosted over the skeleton / error view.
      listenWhen: (_, state) => state is! HomeLoaded,
      listener: (_, _) => _blurProgress.value = 0,
      child: Stack(
        children: [
          Positioned.fill(
            child: BlocBuilder<HomeBloc, HomeState>(
              builder: (context, state) {
                if (state is HomeLoading || state is HomeInitial) {
                  return const HomeSkeleton();
                }
                // A failed catalogue no longer takes the screen with it.
                // Continue Watching is Hive rows and the downloads are files;
                // neither needs a network, and both used to vanish because one
                // cloud provider timed out. HomeContent renders them and puts
                // the reason in a strip above.
                if (state is HomeError) {
                  return HomeContent(
                    catalogue: CatalogueFailed(state.message),
                    blurProgress: _blurProgress,
                  );
                }
                if (state is HomeLoaded) {
                  return HomeContent(
                    catalogue: CatalogueReady(state),
                    blurProgress: _blurProgress,
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: _blurProgress,
                  builder: (_, progress, _) =>
                      HomeTopBar(blurProgress: progress),
                ),
                // Collapses to nothing while the backend is healthy, so the bar
                // keeps its exact previous geometry in the normal case.
                const BackendOutageBanner(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
