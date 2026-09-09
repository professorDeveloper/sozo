import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:soplay/core/deeplink/deeplink_service.dart';
import 'package:soplay/core/js/dart_fetch.dart';
import 'package:soplay/core/js/extractor_cache.dart';
import 'package:soplay/core/js/extractor_remote.dart';
import 'package:soplay/core/js/js_runtime_service.dart';
import 'package:soplay/core/js/provider_registry.dart';
import 'package:soplay/core/extractor/extractor_runner.dart';
import 'package:soplay/core/extractor/provider_manager.dart';
import 'package:soplay/core/network/auth_interceptor.dart';
import 'package:soplay/core/network/token_refresher.dart';
import 'package:soplay/core/network/cf_bypass_interceptor.dart';
import 'package:soplay/core/network/cf_bypass_service.dart';
import 'package:soplay/core/network/dio_client.dart';
import 'package:soplay/core/network/logging_interceptor.dart';
import 'package:soplay/core/network/no_internet_interceptor.dart';
import 'package:soplay/core/network/provider_interceptor.dart';
import 'package:soplay/core/player/local_hls_proxy.dart';
import 'package:soplay/core/player/webview_stream_extractor.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/discord/discord_presence_service.dart';
import 'package:soplay/core/trailer/trailer_service.dart';
import 'package:soplay/core/theme/theme_controller.dart';
import 'package:soplay/features/anilist/data/airing_reminders.dart';
import 'package:soplay/features/live_tv/data/live_tv_service.dart';
import 'package:soplay/features/remote/data/remote_control_service.dart';
import 'package:soplay/features/streak/data/streak_remote_data_source.dart';
import 'package:soplay/features/streak/data/streak_service.dart';
import 'package:soplay/features/watch_party/data/watch_party_remote_data_source.dart';
import 'package:soplay/features/watch_party/data/watch_party_service.dart';
import 'package:soplay/features/download/data/datasources/download_local_data_source.dart';
import 'package:soplay/features/download/data/datasources/download_native_data_source.dart';
import 'package:soplay/features/download/data/datasources/download_transfer_data_source.dart';
import 'package:soplay/features/download/data/repositories/download_repository_impl.dart';
import 'package:soplay/features/download/data/storage/download_storage.dart';
import 'package:soplay/features/download/domain/repositories/download_repository.dart';
import 'package:soplay/features/download/domain/usecases/control_download_usecase.dart';
import 'package:soplay/features/download/domain/usecases/download_location_usecase.dart';
import 'package:soplay/features/download/domain/usecases/download_storage_usecase.dart';
import 'package:soplay/features/download/domain/usecases/enqueue_download_usecase.dart';
import 'package:soplay/features/download/domain/usecases/export_download_usecase.dart';
import 'package:soplay/features/download/domain/usecases/get_downloads_usecase.dart';
import 'package:soplay/features/download/domain/usecases/remove_download_usecase.dart';
import 'package:soplay/features/download/domain/usecases/verify_downloads_usecase.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/history/data/history_sync_remote_data_source.dart';
import 'package:soplay/features/history/data/history_sync_service.dart';
import 'package:soplay/features/anilist/data/anilist_link_store.dart';
import 'package:soplay/features/mal/data/mal_link_store.dart';
import 'package:soplay/features/mal/data/mal_service.dart';
import 'package:soplay/features/mal/data/mal_tracker.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/anilist/data/anilist_tracker.dart';
import 'package:soplay/features/detail/data/aniskip_service.dart';
import 'package:soplay/features/profile/data/backup_service.dart';
import 'package:soplay/features/detail/domain/services/alternate_source_service.dart';
import 'package:soplay/features/profile/domain/services/provider_probe.dart';
import 'package:soplay/features/auth/data/services/google_auth_service.dart';
import 'package:soplay/features/auth/domain/usecases/forgot_password_usecase.dart';
import 'package:soplay/features/auth/domain/usecases/google_login_usecase.dart';
import 'package:soplay/features/auth/domain/usecases/register_usecase.dart';
import 'package:soplay/features/auth/domain/usecases/resend_otp_usecase.dart';
import 'package:soplay/features/auth/domain/usecases/verify_otp_usecase.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_event.dart';
import 'package:soplay/features/app_lock/data/datasources/app_lock_local_data_source.dart';
import 'package:soplay/features/app_lock/data/repositories/app_lock_repository_impl.dart';
import 'package:soplay/features/app_lock/domain/repositories/app_lock_repository.dart';
import 'package:soplay/features/app_updater/data/datasources/app_updater_data_source.dart';
import 'package:soplay/features/app_updater/data/repositories/app_updater_repository_impl.dart';
import 'package:soplay/features/app_updater/domain/repositories/app_updater_repository.dart';
import 'package:soplay/features/app_updater/presentation/services/update_checker.dart';
import 'package:soplay/features/banners/data/datasources/banners_data_source.dart';
import 'package:soplay/features/banners/data/repositories/banners_repository_impl.dart';
import 'package:soplay/features/banners/domain/repositories/banners_repository.dart';
import 'package:soplay/features/banners/presentation/bloc/banners_bloc.dart';
import 'package:soplay/features/comments/data/datasources/comments_data_source.dart';
import 'package:soplay/features/comments/data/repositories/comments_repository_impl.dart';
import 'package:soplay/features/comments/domain/repositories/comments_repository.dart';
import 'package:soplay/features/comments/presentation/blocs/comments_bloc/comments_bloc.dart';
import 'package:soplay/features/notifications/data/datasources/notifications_data_source.dart';
import 'package:soplay/features/notifications/data/repositories/notifications_repository_impl.dart';
import 'package:soplay/features/notifications/data/services/notification_service.dart';
import 'package:soplay/features/notifications/domain/repositories/notifications_repository.dart';
import 'package:soplay/features/notifications/presentation/bloc/notifications_bloc.dart';
import 'package:soplay/features/extensions/data/catalog_repository.dart';
import 'package:soplay/features/extensions/data/extension_repo_repository.dart';
import 'package:soplay/features/extensions/data/mangayomi_bridge.dart';
import 'package:soplay/features/extensions/data/mangayomi_repo_store.dart';
import 'package:soplay/features/extensions/data/mangayomi_runtime.dart';
import 'package:soplay/features/reports/data/datasources/reports_data_source.dart';
import 'package:soplay/features/reports/data/repositories/reports_repository_impl.dart';
import 'package:soplay/features/reports/domain/repositories/reports_repository.dart';
import 'package:soplay/features/detail/data/datasources/detail_data_source.dart';
import 'package:soplay/features/detail/data/repositories/detail_repository_impl.dart';
import 'package:soplay/features/detail/domain/repositories/detail_repository.dart';
import 'package:soplay/features/detail/domain/usecases/get_detail_usecase.dart';
import 'package:soplay/features/detail/domain/usecases/get_episodes_usecase.dart';
import 'package:soplay/features/detail/domain/usecases/get_pages_usecase.dart';
import 'package:soplay/features/detail/domain/usecases/resolve_media_usecase.dart';
import 'package:soplay/features/detail/presentation/blocs/detail_bloc/detail_bloc.dart';
import 'package:soplay/features/detail/presentation/blocs/episodes_bloc/episodes_bloc.dart';
import 'package:soplay/features/home/data/datasources/home_data_source.dart';
import 'package:soplay/features/home/data/repositories/home_repository_imp.dart';
import 'package:soplay/features/home/domain/repositories/home_repository.dart';
import 'package:soplay/features/home/domain/usecase/view_all_usecase.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_bloc.dart';
import 'package:soplay/features/home/presentation/bloc/view_all/view_all_bloc.dart';
import 'package:soplay/features/profile/data/datasources/provider_data_source.dart';
import 'package:soplay/features/profile/data/repositories/provider_repository_impl.dart';
import 'package:soplay/features/profile/domain/repositories/provider_repository.dart';
import 'package:soplay/features/profile/domain/usecases/get_providers_usecase.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/core/analytics/analytics.dart';
import 'package:soplay/features/anilist/data/anilist_api.dart';
import 'package:soplay/features/search/data/datasources/search_data_source.dart';
import 'package:soplay/features/search/data/title_suggestion_service.dart';
import 'package:soplay/features/search/data/repositories/search_repository_imp.dart';
import 'package:soplay/features/search/domain/services/cross_search_engine.dart';
import 'package:soplay/features/tracker/data/follow_service.dart';
import 'package:soplay/features/search/domain/repositories/search_repository.dart';
import 'package:soplay/features/search/domain/usecases/genre_usecase.dart';
import 'package:soplay/features/search/domain/usecases/search_usecase.dart';
import 'package:soplay/features/shorts/data/datasources/shorts_remote_data_source.dart';
import 'package:soplay/features/shorts/data/repositories/shorts_repository_impl.dart';
import 'package:soplay/features/shorts/domain/repositories/shorts_repository.dart';
import 'package:soplay/features/shorts/domain/usecases/get_short_usecase.dart';
import 'package:soplay/features/shorts/domain/usecases/get_shorts_usecase.dart';
import 'package:soplay/features/shorts/domain/usecases/increase_short_view_usecase.dart';
import 'package:soplay/features/shorts/domain/usecases/toggle_short_like_usecase.dart';
import 'package:soplay/features/shorts/presentation/bloc/shorts_bloc.dart';
import 'package:soplay/features/trivia/data/datasources/trivia_remote_data_source.dart';
import 'package:soplay/features/trivia/data/repositories/trivia_repository_impl.dart';
import 'package:soplay/features/trivia/domain/repositories/trivia_repository.dart';
import 'package:soplay/features/trivia/domain/usecases/complete_round_usecase.dart';
import 'package:soplay/features/trivia/domain/usecases/create_challenge_usecase.dart';
import 'package:soplay/features/trivia/domain/usecases/create_round_usecase.dart';
import 'package:soplay/features/trivia/domain/usecases/get_actor_profile_usecase.dart';
import 'package:soplay/features/trivia/domain/usecases/get_challenge_usecase.dart';
import 'package:soplay/features/trivia/domain/usecases/get_leaderboard_usecase.dart';
import 'package:soplay/features/trivia/domain/usecases/get_popular_cast_usecase.dart';
import 'package:soplay/features/trivia/domain/usecases/get_top_fans_usecase.dart';
import 'package:soplay/features/trivia/domain/usecases/join_challenge_usecase.dart';
import 'package:soplay/features/trivia/domain/usecases/resume_round_usecase.dart';
import 'package:soplay/features/trivia/domain/usecases/search_cast_usecase.dart';
import 'package:soplay/features/trivia/domain/usecases/start_clip_usecase.dart';
import 'package:soplay/features/trivia/domain/usecases/submit_answer_usecase.dart';
import 'package:soplay/features/trivia/presentation/bloc/cast/cast_bloc.dart';
import 'package:soplay/features/trivia/presentation/bloc/challenge/challenge_bloc.dart';
import 'package:soplay/features/trivia/presentation/bloc/game/game_bloc.dart';
import 'package:soplay/features/trivia/presentation/bloc/hub/trivia_hub_bloc.dart';
import 'package:soplay/features/trivia/presentation/bloc/leaderboard/leaderboard_bloc.dart';
import 'package:soplay/features/trivia/presentation/bloc/topfans/top_fans_bloc.dart';
import 'package:soplay/features/detail/presentation/blocs/favorite_bloc/favorite_bloc.dart';
import 'package:soplay/features/my_list/data/datasources/my_list_local_data_source.dart';
import 'package:soplay/features/my_list/data/datasources/my_list_remote_data_source.dart';
import 'package:soplay/features/user_lists/data/datasources/user_lists_remote_data_source.dart';
import 'package:soplay/features/user_lists/data/repositories/user_lists_repository_impl.dart';
import 'package:soplay/features/user_lists/domain/repositories/user_lists_repository.dart';
import 'package:soplay/features/my_list/data/private_list_service.dart';
import 'package:soplay/features/my_list/data/repositories/my_list_repository_impl.dart';
import 'package:soplay/features/my_list/domain/repositories/my_list_repository.dart';
import 'package:soplay/features/my_list/domain/usecases/add_favorite_usecase.dart';
import 'package:soplay/features/my_list/domain/usecases/get_favorites_usecase.dart';
import 'package:soplay/features/my_list/domain/usecases/remove_favorite_usecase.dart';
import 'package:soplay/features/my_list/domain/usecases/sync_favorites_usecase.dart';
import 'package:soplay/features/search/presentation/blocs/search_bloc.dart';

import '../../features/auth/data/datasources/auth_remote_data_source.dart';
import '../../features/link_tv/data/datasources/link_tv_remote_data_source.dart';
import '../../features/link_tv/data/repositories/link_tv_repository_impl.dart';
import '../../features/link_tv/domain/repositories/link_tv_repository.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/domain/usecases/login_usecase.dart';
import '../../features/home/domain/usecase/home_usecase.dart';
import '../navigation/nav_controller.dart';

final getIt = GetIt.instance;

Future<void> configureDependencies() async {
  getIt.registerSingleton<DeeplinkService>(DeeplinkService());
  getIt.registerSingleton<HiveService>(HiveService());
  // Eager, and immediately after Hive: the constructor reads the stored accent
  // and AMOLED preference and installs the palette synchronously, so the first
  // frame after runApp() is already painted in the user's colours instead of
  // flashing the default red.
  getIt.registerSingleton<ThemeController>(
    ThemeController(getIt<HiveService>()),
  );
  getIt.registerSingleton<HistoryService>(HistoryService());
  // Downloads. The repository owns the queue, the filesystem and whichever of
  // the two transfer engines this platform uses; everything above it sees use
  // cases. `initialize()` is deliberately NOT awaited here — it resolves the
  // storage root and re-verifies every row against the disk, and a startup
  // that blocks on a filesystem sweep is a startup that stutters. main() kicks
  // it off, and every entry point on the repository awaits it itself.
  getIt.registerSingleton<DownloadStorage>(DownloadStorage());
  getIt.registerSingleton<DownloadLocalDataSource>(DownloadLocalDataSource());
  getIt.registerSingleton<DownloadNativeDataSource>(
    const DownloadNativeDataSource(),
  );
  getIt.registerSingleton<DownloadTransferDataSource>(
    DownloadTransferDataSource(),
  );
  getIt.registerSingleton<DownloadRepository>(
    DownloadRepositoryImpl(
      local: getIt<DownloadLocalDataSource>(),
      storage: getIt<DownloadStorage>(),
      native: getIt<DownloadNativeDataSource>(),
      transfer: getIt<DownloadTransferDataSource>(),
      hive: getIt<HiveService>(),
    ),
  );
  getIt.registerLazySingleton<EnqueueDownloadUseCase>(
    () => EnqueueDownloadUseCase(getIt<DownloadRepository>()),
  );
  getIt.registerLazySingleton<GetDownloadsUseCase>(
    () => GetDownloadsUseCase(getIt<DownloadRepository>()),
  );
  getIt.registerLazySingleton<ControlDownloadUseCase>(
    () => ControlDownloadUseCase(getIt<DownloadRepository>()),
  );
  getIt.registerLazySingleton<RemoveDownloadUseCase>(
    () => RemoveDownloadUseCase(getIt<DownloadRepository>()),
  );
  getIt.registerLazySingleton<VerifyDownloadsUseCase>(
    () => VerifyDownloadsUseCase(getIt<DownloadRepository>()),
  );
  getIt.registerLazySingleton<DownloadStorageUseCase>(
    () => DownloadStorageUseCase(getIt<DownloadRepository>()),
  );
  getIt.registerLazySingleton<ExportDownloadUseCase>(
    () => ExportDownloadUseCase(getIt<DownloadRepository>()),
  );
  getIt.registerLazySingleton<DownloadLocationUseCase>(
    () => DownloadLocationUseCase(getIt<DownloadRepository>()),
  );
  // Lazy: a session that never opens a detail page never constructs the
  // YouTube client, and constructing one opens an HTTP client of its own.
  getIt.registerLazySingleton<TrailerService>(() => TrailerService());
  // Lazy and inert until switched on: constructing it opens nothing and
  // connects to nothing.
  getIt.registerLazySingleton<DiscordPresenceService>(
    () => DiscordPresenceService(),
  );

  final dio = DioClient.instance;
  dio.interceptors.add(ProviderInterceptor(hiveService: getIt<HiveService>()));
  dio.interceptors.add(LoggingInterceptor());
  dio.interceptors.add(NoInternetInterceptor());
  dio.interceptors.add(
    AuthInterceptor(
      hiveService: getIt<HiveService>(),
      dio: dio,
      onSessionExpired: () {
        if (getIt.isRegistered<AuthBloc>()) {
          getIt<AuthBloc>().add(AuthSessionExpired());
        }
      },
    ),
  );
  getIt.registerSingleton<CfBypassService>(CfBypassService());
  dio.interceptors.add(
    CfBypassInterceptor(dio: dio, service: getIt<CfBypassService>()),
  );
  getIt.registerSingleton<Dio>(dio);

  // Watch history sync. Registered after Dio because it rides the authenticated
  // client: the bearer token and its silent refresh come from the existing
  // interceptor rather than being re-implemented here.
  getIt.registerSingleton<HistorySyncRemoteDataSource>(
    HistorySyncRemoteDataSource(dio: getIt<Dio>()),
  );
  getIt.registerSingleton<HistorySyncService>(
    HistorySyncService(
      remote: getIt<HistorySyncRemoteDataSource>(),
      local: getIt<HistoryService>(),
    ),
  );

  // AniList. Rides the authenticated backend client because the link lives on
  // the Sozo account — the client secret stays on the server, and a TV signed
  // into the same account inherits the connection without its own sign-in.
  getIt.registerLazySingleton<AiringReminders>(
    () => AiringReminders(
      notifications: getIt<NotificationService>(),
      hive: getIt<HiveService>(),
    ),
  );
  getIt.registerLazySingleton<LiveTvService>(
    () => LiveTvService(dio: getIt<Dio>()),
  );
  getIt.registerLazySingleton<RemoteControlService>(
    () => RemoteControlService(dio: getIt<Dio>()),
  );
  getIt.registerSingleton<AnilistLinkStore>(AnilistLinkStore());
  getIt.registerSingleton<AnilistService>(
    AnilistService(
      backendDio: getIt<Dio>(),
      hive: getIt<HiveService>(),
      links: getIt<AnilistLinkStore>(),
    ),
  );
  getIt.registerLazySingleton<AniSkipService>(() => AniSkipService());
  getIt.registerLazySingleton<BackupService>(() => BackupService());

  getIt.registerLazySingleton<ProviderProbe>(
    () => ProviderProbe(
      engine: getIt<CrossSearchEngine>(),
      episodes: getIt<GetEpisodesUseCase>(),
      resolve: getIt<ResolveMediaUseCase>(),
      dio: getIt<Dio>(),
    ),
  );

  getIt.registerLazySingleton<AlternateSourceService>(
    () => AlternateSourceService(
      engine: getIt<CrossSearchEngine>(),
      providers: getIt<GetProvidersUseCase>(),
      episodes: getIt<GetEpisodesUseCase>(),
    ),
  );

  getIt.registerSingleton<AnilistTracker>(
    AnilistTracker(
      service: getIt<AnilistService>(),
      links: getIt<AnilistLinkStore>(),
    ),
  );

  // MyAnimeList. Same account-owned shape as AniList above, with one dependency
  // that looks odd and is deliberate: the MAL tracker holds the AniList one as a
  // MATCHER. AniList search needs no token, and it publishes the MAL id for the
  // same entry, so a title matched once serves both trackers instead of being
  // matched twice — and matched twice is matched wrong twice.
  getIt.registerSingleton<MalLinkStore>(MalLinkStore());
  getIt.registerSingleton<MalService>(
    MalService(
      backendDio: getIt<Dio>(),
      hive: getIt<HiveService>(),
      links: getIt<MalLinkStore>(),
    ),
  );
  getIt.registerSingleton<MalTracker>(
    MalTracker(
      service: getIt<MalService>(),
      links: getIt<MalLinkStore>(),
      anilist: getIt<AnilistTracker>(),
    ),
  );

  getIt.registerSingleton<AuthRemoteDataSource>(
    AuthRemoteDataSource(dio: getIt<Dio>()),
  );
  getIt.registerSingleton<LinkTvRemoteDataSource>(
    LinkTvRemoteDataSource(dio: getIt<Dio>()),
  );
  getIt.registerSingleton<HomeDataSource>(HomeDataSource(dio: getIt<Dio>()));
  getIt.registerSingleton<DetailDataSource>(
    DetailDataSource(dio: getIt<Dio>()),
  );
  getIt.registerSingleton<SearchDataSource>(
    SearchDataSource(dio: getIt<Dio>()),
  );

  getIt.registerSingleton<GoogleAuthService>(GoogleAuthService());
  getIt.registerSingleton<AuthRepository>(
    AuthRepositoryImpl(getIt<AuthRemoteDataSource>(), getIt<HiveService>()),
  );
  getIt.registerSingleton<LinkTvRepository>(
    LinkTvRepositoryImpl(getIt<LinkTvRemoteDataSource>()),
  );
  getIt.registerSingleton<ProviderDataSource>(
    ProviderDataSource(dio: getIt<Dio>()),
  );
  getIt.registerSingleton<ProviderRegistry>(
    ProviderRegistry(source: getIt<ProviderDataSource>()),
  );
  getIt.registerSingleton<ExtractorRemote>(
    ExtractorRemote(dio: getIt<Dio>()),
  );
  getIt.registerSingleton<ExtractorCache>(ExtractorCache());
  getIt.registerSingleton<DartFetch>(DartFetch.create(
    cfService:  getIt<CfBypassService>(),
    backendDio: getIt<Dio>(),
  ));
  getIt.registerSingleton<StreakRemoteDataSource>(
    StreakRemoteDataSource(dio: getIt<Dio>()),
  );
  getIt.registerSingleton<StreakService>(
    StreakService(
      remote: getIt<StreakRemoteDataSource>(),
      hive: getIt<HiveService>(),
    ),
  );
  getIt.registerLazySingleton<TokenRefresher>(
    () => TokenRefresher(getIt<HiveService>()),
  );
  getIt.registerSingleton<WatchPartyRemoteDataSource>(
    WatchPartyRemoteDataSource(dio: getIt<Dio>()),
  );
  getIt.registerSingleton<WatchPartyService>(
    WatchPartyService(
      remote: getIt<WatchPartyRemoteDataSource>(),
      hive: getIt<HiveService>(),
      tokenRefresher: getIt<TokenRefresher>(),
    ),
  );
  getIt.registerLazySingleton<LocalHlsProxy>(
    () => LocalHlsProxy(getIt<DartFetch>().dio),
  );
  getIt.registerSingleton<JsRuntimeService>(
    JsRuntimeService(
      remote: getIt<ExtractorRemote>(),
      cache: getIt<ExtractorCache>(),
      dartFetch: getIt<DartFetch>(),
      providers: getIt<ProviderRegistry>(),
    ),
  );
  // Mangayomi JS extensions. Registered unconditionally — unlike the Kotlin
  // hosts these run wherever there is a WebView, which is the whole reason they
  // exist here (iOS/macOS/Windows extension support).
  getIt.registerLazySingleton<MangayomiRepoStore>(
    () => MangayomiRepoStore(dio: getIt<Dio>()),
  );
  getIt.registerLazySingleton<MangayomiRuntime>(
    () => MangayomiRuntime(
      store: getIt<MangayomiRepoStore>(),
      dartFetch: getIt<DartFetch>(),
    ),
  );
  getIt.registerLazySingleton<MangayomiBridge>(
    () => MangayomiBridge(
      runtime: getIt<MangayomiRuntime>(),
      store: getIt<MangayomiRepoStore>(),
    ),
  );
  getIt.registerLazySingleton<ExtractorRunner>(
    () => ExtractorRunner(dio: getIt<Dio>()),
  );
  getIt.registerLazySingleton<ProviderManager>(
    () => ProviderManager(
      detailDataSource: getIt<DetailDataSource>(),
      homeDataSource: getIt<HomeDataSource>(),
      searchDataSource: getIt<SearchDataSource>(),
      extractor: getIt<ExtractorRunner>(),
      hiveService: getIt<HiveService>(),
    ),
  );
  getIt.registerSingleton<HomeRepository>(
    HomeRepositoryImp(
      getIt<HomeDataSource>(),
      mangayomi: getIt<MangayomiBridge>(),
      jsRuntime: getIt<JsRuntimeService>(),
      hive: getIt<HiveService>(),
    ),
  );
  getIt.registerSingleton<SearchRepository>(
    SearchRepositoryImp(
      dataSource: getIt<SearchDataSource>(),
      mangayomi: getIt<MangayomiBridge>(),
      jsRuntime: getIt<JsRuntimeService>(),
      hive: getIt<HiveService>(),
    ),
  );
  // Metadata autocomplete for the search field. Lazy because a user who never
  // opens Search never pays for its Dio client, and a singleton because its
  // whole value is the cache it accumulates while someone types.
  // Registered before anything that reports, and a singleton because the SDK
  // holds one queue. Started separately in main() — construction must not do
  // I/O, so a test that builds the graph does not reach the network.
  getIt.registerLazySingleton<Analytics>(
    () => Analytics(
      // Read per call, not captured: incognito is a toggle someone flips
      // mid-session and the whole point is that it takes effect then.
      suppressed: () => getIt<HiveService>().isIncognito,
    ),
  );
  getIt.registerLazySingleton<TitleSuggestionService>(
    () => TitleSuggestionService(
      anilist: AnilistApi(),
      dataSource: getIt<SearchDataSource>(),
    ),
  );
  getIt.registerLazySingleton<CrossSearchEngine>(
    () => CrossSearchEngine(
      jsRuntime: getIt<JsRuntimeService>(),
      dataSource: getIt<SearchDataSource>(),
      mangayomi: getIt<MangayomiBridge>(),
    ),
  );
  getIt.registerSingleton<WebViewStreamExtractor>(WebViewStreamExtractor());
  getIt.registerSingleton<DetailRepository>(
    DetailRepositoryImpl(
      getIt<DetailDataSource>(),
      mangayomi: getIt<MangayomiBridge>(),
      jsRuntime: getIt<JsRuntimeService>(),
      hive: getIt<HiveService>(),
    ),
  );
  getIt.registerSingleton<CommentsDataSource>(
    CommentsDataSource(dio: getIt<Dio>()),
  );
  getIt.registerSingleton<ShortsRemoteDataSource>(
    ShortsRemoteDataSource(dio: getIt<Dio>()),
  );
  getIt.registerSingleton<CommentsRepository>(
    CommentsRepositoryImpl(getIt<CommentsDataSource>()),
  );
  getIt.registerSingleton<ProviderRepository>(
    ProviderRepositoryImpl(getIt<ProviderDataSource>(), getIt<HiveService>()),
  );
  getIt.registerSingleton<ShortsRepository>(
    ShortsRepositoryImpl(getIt<ShortsRemoteDataSource>()),
  );
  getIt.registerSingleton<NotificationsDataSource>(
    NotificationsDataSource(dio: getIt<Dio>()),
  );
  getIt.registerSingleton<NotificationsRepository>(
    NotificationsRepositoryImpl(getIt<NotificationsDataSource>()),
  );
  getIt.registerSingleton<NotificationService>(
    NotificationService(repository: getIt<NotificationsRepository>()),
  );
  getIt.registerSingleton<BannersDataSource>(
    BannersDataSource(dio: getIt<Dio>()),
  );
  getIt.registerSingleton<BannersRepository>(
    BannersRepositoryImpl(getIt<BannersDataSource>()),
  );
  // Recommended extension repos for the sources pages — backend-curated with a
  // compiled-in fallback, so the list survives an outage.
  getIt.registerLazySingleton<CatalogRepository>(
    () => CatalogRepository(dio: getIt<Dio>()),
  );
  getIt.registerLazySingleton<ExtensionRepoRepository>(
    () => ExtensionRepoRepository(dio: getIt<Dio>()),
  );
  getIt.registerSingleton<ReportsDataSource>(
    ReportsDataSource(dio: getIt<Dio>()),
  );
  getIt.registerSingleton<ReportsRepository>(
    ReportsRepositoryImpl(getIt<ReportsDataSource>()),
  );
  getIt.registerSingleton<AppUpdaterDataSource>(
    AppUpdaterDataSource(dio: getIt<Dio>()),
  );
  getIt.registerSingleton<AppUpdaterRepository>(
    AppUpdaterRepositoryImpl(getIt<AppUpdaterDataSource>()),
  );
  getIt.registerSingleton<UpdateChecker>(
    UpdateChecker(repository: getIt<AppUpdaterRepository>()),
  );

  getIt.registerSingleton<MyListRemoteDataSource>(
    MyListRemoteDataSource(dio: getIt<Dio>()),
  );
  getIt.registerSingleton<MyListLocalDataSource>(
    MyListLocalDataSource(),
  );
  getIt.registerSingleton<PrivateListService>(PrivateListService());
  getIt.registerSingleton<MyListRepository>(
    MyListRepositoryImpl(
      getIt<MyListRemoteDataSource>(),
      getIt<MyListLocalDataSource>(),
      getIt<HiveService>(),
    ),
  );
  // User-curated lists (Watch Later / Watched). One repository serves both —
  // the kind is a parameter, mirroring the server's single handler.
  getIt.registerSingleton<UserListsRemoteDataSource>(
    UserListsRemoteDataSource(dio: getIt<Dio>()),
  );
  getIt.registerSingleton<UserListsRepository>(
    UserListsRepositoryImpl(
      getIt<UserListsRemoteDataSource>(),
      getIt<HiveService>(),
    ),
  );

  getIt.registerSingleton<GetFavoritesUseCase>(
    GetFavoritesUseCase(getIt<MyListRepository>()),
  );
  getIt.registerSingleton<AddFavoriteUseCase>(
    AddFavoriteUseCase(getIt<MyListRepository>()),
  );
  getIt.registerSingleton<RemoveFavoriteUseCase>(
    RemoveFavoriteUseCase(getIt<MyListRepository>()),
  );
  getIt.registerSingleton<SyncFavoritesUseCase>(
    SyncFavoritesUseCase(getIt<MyListRepository>()),
  );
  getIt.registerSingleton<GetShortsUseCase>(
    GetShortsUseCase(getIt<ShortsRepository>()),
  );
  getIt.registerSingleton<GetShortUseCase>(
    GetShortUseCase(getIt<ShortsRepository>()),
  );
  getIt.registerSingleton<IncreaseShortViewUseCase>(
    IncreaseShortViewUseCase(getIt<ShortsRepository>()),
  );
  getIt.registerSingleton<ToggleShortLikeUseCase>(
    ToggleShortLikeUseCase(getIt<ShortsRepository>()),
  );

  // ---- Buff (trivia) ----
  getIt.registerSingleton<TriviaRemoteDataSource>(
    TriviaRemoteDataSource(dio: getIt<Dio>()),
  );
  getIt.registerSingleton<TriviaRepository>(
    TriviaRepositoryImpl(getIt<TriviaRemoteDataSource>()),
  );
  getIt.registerSingleton<CreateRoundUseCase>(
    CreateRoundUseCase(getIt<TriviaRepository>()),
  );
  getIt.registerSingleton<StartClipUseCase>(
    StartClipUseCase(getIt<TriviaRepository>()),
  );
  getIt.registerSingleton<SubmitAnswerUseCase>(
    SubmitAnswerUseCase(getIt<TriviaRepository>()),
  );
  getIt.registerSingleton<CompleteRoundUseCase>(
    CompleteRoundUseCase(getIt<TriviaRepository>()),
  );
  getIt.registerSingleton<ResumeRoundUseCase>(
    ResumeRoundUseCase(getIt<TriviaRepository>()),
  );
  getIt.registerSingleton<SearchCastUseCase>(
    SearchCastUseCase(getIt<TriviaRepository>()),
  );
  getIt.registerSingleton<GetPopularCastUseCase>(
    GetPopularCastUseCase(getIt<TriviaRepository>()),
  );
  getIt.registerSingleton<GetActorProfileUseCase>(
    GetActorProfileUseCase(getIt<TriviaRepository>()),
  );
  getIt.registerSingleton<GetLeaderboardUseCase>(
    GetLeaderboardUseCase(getIt<TriviaRepository>()),
  );
  getIt.registerSingleton<GetTopFansUseCase>(
    GetTopFansUseCase(getIt<TriviaRepository>()),
  );
  getIt.registerSingleton<CreateChallengeUseCase>(
    CreateChallengeUseCase(getIt<TriviaRepository>()),
  );
  getIt.registerSingleton<GetChallengeUseCase>(
    GetChallengeUseCase(getIt<TriviaRepository>()),
  );
  getIt.registerSingleton<JoinChallengeUseCase>(
    JoinChallengeUseCase(getIt<TriviaRepository>()),
  );

  getIt.registerSingleton<GetDetailUseCase>(
    GetDetailUseCase(getIt<DetailRepository>()),
  );
  getIt.registerSingleton<GetEpisodesUseCase>(
    GetEpisodesUseCase(getIt<DetailRepository>()),
  );
  getIt.registerSingleton<FollowService>(
    FollowService(
      hive: getIt<HiveService>(),
      getEpisodes: getIt<GetEpisodesUseCase>(),
      notifications: getIt<NotificationService>(),
    ),
  );
  getIt.registerSingleton<ResolveMediaUseCase>(
    ResolveMediaUseCase(getIt<DetailRepository>()),
  );
  getIt.registerSingleton<GetPagesUseCase>(
    GetPagesUseCase(getIt<DetailRepository>()),
  );
  getIt.registerSingleton<ViewAllUseCase>(
    ViewAllUseCase(getIt<HomeRepository>()),
  );
  getIt.registerSingleton<LoginUseCase>(LoginUseCase(getIt<AuthRepository>()));
  getIt.registerSingleton<GoogleLoginUseCase>(
    GoogleLoginUseCase(getIt<AuthRepository>()),
  );
  getIt.registerSingleton<RegisterUseCase>(
    RegisterUseCase(getIt<AuthRepository>()),
  );
  getIt.registerSingleton<VerifyOtpUseCase>(
    VerifyOtpUseCase(getIt<AuthRepository>()),
  );
  getIt.registerSingleton<RequestPasswordResetUseCase>(
    RequestPasswordResetUseCase(getIt<AuthRepository>()),
  );
  getIt.registerSingleton<ResetPasswordUseCase>(
    ResetPasswordUseCase(getIt<AuthRepository>()),
  );
  getIt.registerSingleton<ResendOtpUseCase>(
    ResendOtpUseCase(getIt<AuthRepository>()),
  );
  getIt.registerSingleton<HomeUseCase>(HomeUseCase(getIt<HomeRepository>()));
  getIt.registerSingleton<SearchUseCase>(
    SearchUseCase(repository: getIt<SearchRepository>()),
  );
  getIt.registerSingleton<GenreUseCase>(
    GenreUseCase(repository: getIt<SearchRepository>()),
  );
  getIt.registerSingleton<GetProvidersUseCase>(
    GetProvidersUseCase(getIt<ProviderRepository>()),
  );

  getIt.registerLazySingleton<AuthBloc>(
    () => AuthBloc(
      loginUseCase: getIt<LoginUseCase>(),
      googleLoginUseCase: getIt<GoogleLoginUseCase>(),
      googleAuthService: getIt<GoogleAuthService>(),
      registerUseCase: getIt<RegisterUseCase>(),
      verifyOtpUseCase: getIt<VerifyOtpUseCase>(),
      resendOtpUseCase: getIt<ResendOtpUseCase>(),
      requestPasswordResetUseCase: getIt<RequestPasswordResetUseCase>(),
      resetPasswordUseCase: getIt<ResetPasswordUseCase>(),
      authRepository: getIt<AuthRepository>(),
      hiveService: getIt<HiveService>(),
      notificationService: getIt<NotificationService>(),
      syncFavorites: getIt<SyncFavoritesUseCase>(),
    ),
  );
  getIt.registerFactory(
    () => NotificationsBloc(repository: getIt<NotificationsRepository>()),
  );
  getIt.registerFactory(
    () => BannersBloc(repository: getIt<BannersRepository>()),
  );
  getIt.registerFactory(() => DetailBloc(useCase: getIt<GetDetailUseCase>()));
  getIt.registerFactory(
    () => FavoriteBloc(
      addFavorite: getIt<AddFavoriteUseCase>(),
      removeFavorite: getIt<RemoveFavoriteUseCase>(),
      local: getIt<MyListLocalDataSource>(),
    ),
  );
  getIt.registerFactory(
    () => EpisodesBloc(useCase: getIt<GetEpisodesUseCase>()),
  );
  getIt.registerFactory(() => ViewAllBloc(useCase: getIt<ViewAllUseCase>()));
  getIt.registerFactory(() => HomeBloc(useCase: getIt<HomeUseCase>()));
  getIt.registerFactory(
    () => SearchBloc(
      searchUseCase: getIt<SearchUseCase>(),
      genreUseCase: getIt<GenreUseCase>(),
      suggestions: getIt<TitleSuggestionService>(),
    ),
  );
  getIt.registerFactory(
    () => ShortsBloc(
      getShorts: getIt<GetShortsUseCase>(),
      increaseView: getIt<IncreaseShortViewUseCase>(),
      toggleLike: getIt<ToggleShortLikeUseCase>(),
      hiveService: getIt<HiveService>(),
    ),
  );
  getIt.registerFactory(
    () => TriviaHubBloc(getLeaderboard: getIt<GetLeaderboardUseCase>()),
  );
  getIt.registerFactory(
    () => CastBloc(
      searchCast: getIt<SearchCastUseCase>(),
      getPopularCast: getIt<GetPopularCastUseCase>(),
    ),
  );
  getIt.registerFactory(
    () => GameBloc(
      createRound: getIt<CreateRoundUseCase>(),
      startClip: getIt<StartClipUseCase>(),
      submitAnswer: getIt<SubmitAnswerUseCase>(),
      completeRound: getIt<CompleteRoundUseCase>(),
    ),
  );
  getIt.registerFactory(
    () => LeaderboardBloc(getLeaderboard: getIt<GetLeaderboardUseCase>()),
  );
  getIt.registerFactory(
    () => TopFansBloc(getTopFans: getIt<GetTopFansUseCase>()),
  );
  getIt.registerFactory(
    () => ChallengeBloc(
      getChallenge: getIt<GetChallengeUseCase>(),
      joinChallenge: getIt<JoinChallengeUseCase>(),
    ),
  );
  getIt.registerFactory(
    () => ProviderBloc(
      useCase: getIt<GetProvidersUseCase>(),
      hiveService: getIt<HiveService>(),
      providerManager: getIt<ProviderManager>(),
      providerRegistry: getIt<ProviderRegistry>(),
    ),
  );
  getIt.registerFactory(
    () => CommentsBloc(
      repository: getIt<CommentsRepository>(),
      hiveService: getIt<HiveService>(),
    ),
  );

  getIt.registerSingleton<AppLockLocalDataSource>(
    AppLockLocalDataSource(hiveService: getIt<HiveService>()),
  );
  getIt.registerSingleton<AppLockRepository>(
    AppLockRepositoryImpl(getIt<AppLockLocalDataSource>()),
  );

  getIt.registerLazySingleton<NavController>(() => NavController());
}
