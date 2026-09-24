import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/manga/manga_channel.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/extensions/data/mangayomi_bridge.dart';
import 'package:soplay/core/extractor/provider_manager.dart';
import 'package:soplay/core/js/provider_registry.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/profile/data/models/provider_model.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/profile/domain/entities/providers_snapshot.dart';
import 'package:soplay/features/profile/domain/usecases/get_providers_usecase.dart';
import 'provider_event.dart';
import 'provider_state.dart';

const String _kCloudStreamIcon =
    'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTRzeluIShlMnhgHeVHgTSkvsthvQEK2xaS5A&s';

const String _kAniyomiIcon =
    'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcShNP_m0078YcYRUbudCuZhohC2U143Re4MfQ&s';

const String _kMangayomiIcon =
    'https://raw.githubusercontent.com/kodjodevf/mangayomi/main/assets/app_icons/icon-red.png';

const String _kMangaIcon =
    'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcShNP_m0078YcYRUbudCuZhohC2U143Re4MfQ&s';

class ProviderBloc extends Bloc<ProviderEvent, ProviderState> {
  /// How long the backend provider list gets before the app carries on with
  /// on-device plugins alone. Shorter than Dio's own 15s connect timeout on
  /// purpose: past this point the user is better served by a usable app that
  /// says "offline" than by a spinner that might still resolve.
  static const Duration _backendBudget = Duration(seconds: 8);

  final GetProvidersUseCase useCase;
  final HiveService hiveService;
  final ProviderManager providerManager;
  final ProviderRegistry providerRegistry;

  ProviderBloc({
    required this.useCase,
    required this.hiveService,
    required this.providerManager,
    required this.providerRegistry,
  }) : super(ProviderInitial()) {
    on<ProviderLoad>(
      _onLoad,
      transformer: (events, mapper) => events.asyncExpand(mapper),
    );
    on<ProviderSelect>(_onSelect);
  }

  Future<void> _onLoad(ProviderLoad event, Emitter<ProviderState> emit) async {
    final previous = state;
    if (previous is! ProviderLoaded) {
      emit(ProviderLoading());
    }

    // The on-device plugin hosts are loaded CONCURRENTLY with the backend list,
    // never after it. They talk to Kotlin over a platform channel and need no
    // backend at all, so an unreachable — or, worse, merely *slow* — API must
    // not gate them. Sequentially, a backend hanging until its 15s connect
    // timeout left the whole app on a spinner while every installed extension
    // was already sitting there ready to serve.
    final localCloudStream = <ProviderEntity>[];
    final localAniyomi = <ProviderEntity>[];
    final localManga = <ProviderEntity>[];
    final localMangayomi = <ProviderEntity>[];

    // Kept as its own STRONGLY TYPED future rather than one element of a
    // Future.wait<Object?>. Collapsing it into an untyped list erases
    // Result<ProvidersSnapshot>, and the `case Success(:final value)` pattern
    // then binds `value` as dynamic — so `value.providers.where(...)` builds a
    // `(dynamic) => dynamic` closure that fails Iterable.where's runtime type
    // check, the exception escapes the handler, and the bloc never emits: the
    // provider picker spins forever.
    //
    // Bounded so a black-holed connection (SYN accepted, nothing returned)
    // can't outlast the local legs. A timeout degrades to "offline", which is
    // exactly the right reading.
    final Future<Result<ProvidersSnapshot>?> backend =
        event.localOnly && previous is ProviderLoaded
        ? Future.value(
            Success(
              ProvidersSnapshot(
                providers: previous.providers
                    .where((p) => !p.isServerIndependent)
                    .toList(),
                fromCache: previous.offline,
                cachedAt: previous.cachedAt,
              ),
            ),
          )
        : useCase()
              .timeout(_backendBudget)
              .then<Result<ProvidersSnapshot>?>((r) => r)
              .catchError((Object _) => null);

    final locals = Future.wait<void>([
      _appendCloudStreamProviders(localCloudStream),
      _appendAniyomiProviders(localAniyomi),
      _appendMangaProviders(localManga),
      _appendMangayomiProviders(localMangayomi),
    ]);

    final result = await backend;
    await locals;

    final providers = <ProviderEntity>[];
    var offline = false;
    DateTime? cachedAt;

    switch (result) {
      case Success(:final value):
        providers.addAll(value.providers.where((p) => p.id.trim().isNotEmpty));
        offline = value.fromCache;
        cachedAt = value.cachedAt;
      case Failure():
      case null: // timed out or threw
        // No network list and no cache — local plugins are all we have.
        offline = true;
    }

    providers
      ..addAll(localCloudStream)
      ..addAll(localAniyomi)
      ..addAll(localManga)
      ..addAll(localMangayomi);

    if (providers.isEmpty) {
      if (previous is! ProviderLoaded) {
        emit(ProviderError());
      }
      return;
    }

    final resolvedId = await _resolveAndPersistProvider(
      providers,
      offline: offline,
    );
    // Seeds the memory for installs from before it existed: the source in use
    // is the one its mode should come back to, unless it is a stand-in.
    if (hiveService.getPreOutageProvider().isEmpty) {
      final modeId = resolvedId.contentMode.id;
      if (hiveService.getLastProviderForMode(modeId).isEmpty) {
        await hiveService.saveLastProviderForMode(modeId, resolvedId);
      }
    }

    providerManager.updateProviders(providers);
    providerRegistry.invalidate();

    emit(
      ProviderLoaded(
        providers: providers,
        currentProviderId: resolvedId,
        offline: offline,
        cachedAt: cachedAt,
      ),
    );
  }

  Future<void> _onSelect(
    ProviderSelect event,
    Emitter<ProviderState> emit,
  ) async {
    await hiveService.saveCurrentProvider(event.providerId);
    // An explicit pick supersedes any provider parked by the outage handler,
    // so it is not undone when the backend comes back.
    await hiveService.clearPreOutageProvider();
    // The mode follows the source. Five places select a source and only two
    // moved the mode with it, so picking a manga source from the providers
    // page left Home labelled Watch with manga rows under it.
    final mode = event.providerId.contentMode;
    if (event.remember) {
      await hiveService.saveLastProviderForMode(mode.id, event.providerId);
    }
    if (hiveService.getContentMode() != mode.id) {
      await hiveService.setContentMode(mode.id);
    }
    if (state is ProviderLoaded) {
      final loaded = state as ProviderLoaded;
      emit(
        ProviderLoaded(
          providers: loaded.providers,
          currentProviderId: event.providerId,
          offline: loaded.offline,
          cachedAt: loaded.cachedAt,
        ),
      );
    }
  }

  Future<void> _appendCloudStreamProviders(List<ProviderEntity> into) async {
    if (!CloudStreamChannel.isSupported) return;
    // The one 18+ setting covers video sources too, and for the manga
    // sources' reason: dropped here, a hidden source is also one the resolver
    // will not keep selected.
    final allowAdult = hiveService.showAdultContent;
    try {
      final list = await CloudStreamChannel.ensureLoaded();
      for (final e in list) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final id = (m['id'] as String?)?.trim() ?? '';
        if (id.isEmpty) continue;
        if (m['nsfw'] == true && !allowAdult) continue;
        into.add(
          ProviderModel(
            id: id,
            name: (m['name'] as String?) ?? id,
            image: (m['icon'] as String?)?.isNotEmpty == true
                ? m['icon'] as String
                : _kCloudStreamIcon,
            url: (m['mainUrl'] as String?) ?? '',
            description: (m['repo'] as String?)?.isNotEmpty == true
                ? m['repo'] as String
                : 'CloudStream',
            repo: (m['repo'] as String?)?.trim() ?? '',
            domains: const [],
            mode: 'client',
            category: 'cloudstream',
            lang: (m['lang'] as String?)?.trim() ?? '',
            nsfw: m['nsfw'] == true,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _appendAniyomiProviders(List<ProviderEntity> into) async {
    if (!AniyomiChannel.isSupported) return;
    final allowAdult = hiveService.showAdultContent;
    try {
      final list = await AniyomiChannel.ensureLoaded();
      for (final e in list) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final id = (m['id'] as String?)?.trim() ?? '';
        if (id.isEmpty) continue;
        if (m['nsfw'] == true && !allowAdult) continue;
        into.add(
          ProviderModel(
            id: id,
            name: (m['name'] as String?) ?? id,
            image: (m['icon'] as String?)?.isNotEmpty == true
                ? m['icon'] as String
                : _kAniyomiIcon,
            url: (m['baseUrl'] as String?) ?? '',
            description: (m['repo'] as String?)?.isNotEmpty == true
                ? m['repo'] as String
                : 'Aniyomi',
            repo: (m['repo'] as String?)?.trim() ?? '',
            domains: const [],
            mode: 'client',
            category: 'aniyomi',
            lang: (m['lang'] as String?)?.trim() ?? '',
            nsfw: m['nsfw'] == true,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _appendMangaProviders(List<ProviderEntity> into) async {
    if (!MangaChannel.isSupported) return;
    // Adult manga sources are opt-in. Dropping them here rather than in the
    // picker's own filter is deliberate: everything downstream — the picker,
    // ProviderManager, and _resolveAndPersistProvider — works off this list, so
    // a hidden source is also one the resolver will not keep selected. Turning
    // the setting off therefore retires a dangling 18+ selection on the next
    // load instead of leaving it live but invisible.
    final allowNsfw = hiveService.showAdultContent;
    try {
      final list = await MangaChannel.ensureLoaded();
      for (final e in list) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final id = (m['id'] as String?)?.trim() ?? '';
        if (id.isEmpty) continue;
        if (m['nsfw'] == true && !allowNsfw) continue;
        into.add(
          ProviderModel(
            id: id,
            name: (m['name'] as String?) ?? id,
            image: (m['icon'] as String?)?.isNotEmpty == true
                ? m['icon'] as String
                : _kMangaIcon,
            url: (m['baseUrl'] as String?) ?? '',
            description: (m['repo'] as String?)?.isNotEmpty == true
                ? m['repo'] as String
                : 'Manga',
            repo: (m['repo'] as String?)?.trim() ?? '',
            domains: const [],
            mode: 'client',
            category: 'manga',
            lang: (m['lang'] as String?)?.trim() ?? '',
            nsfw: m['nsfw'] == true,
          ),
        );
      }
    } catch (_) {}
  }

  /// Mangayomi JavaScript extensions.
  ///
  /// The one source kind that is NOT Android-only: these run in the headless
  /// WebView, so they are what makes extensions work on iOS/macOS/Windows.
  /// Adult sources reuse the same opt-in the manga hosts use — one setting for
  /// "show 18+ sources", not one per ecosystem.
  Future<void> _appendMangayomiProviders(List<ProviderEntity> into) async {
    if (!MangayomiBridge.isSupported) return;
    final allowNsfw = hiveService.showAdultContent;
    try {
      final list = getIt<MangayomiBridge>().listProviders(
        includeNsfw: allowNsfw,
      );
      for (final m in list) {
        final id = (m['id'] as String?)?.trim() ?? '';
        if (id.isEmpty) continue;
        into.add(
          ProviderModel(
            id: id,
            name: (m['name'] as String?) ?? id,
            image: (m['icon'] as String?)?.isNotEmpty == true
                ? m['icon'] as String
                : _kMangayomiIcon,
            url: (m['baseUrl'] as String?) ?? '',
            description: (m['repo'] as String?)?.isNotEmpty == true
                ? m['repo'] as String
                : 'Mangayomi',
            repo: (m['repo'] as String?)?.trim() ?? '',
            domains: const [],
            mode: 'client',
            category: 'mangayomi',
            lang: (m['lang'] as String?)?.trim() ?? '',
            nsfw: m['nsfw'] == true,
          ),
        );
      }
    } catch (_) {}
  }

  /// Picks the provider to run with and keeps Hive in step, because the home,
  /// search and detail repositories all read the current id straight out of
  /// Hive — a selection that lived only in bloc state would leave them calling
  /// the dead server while the UI showed a working plugin.
  ///
  /// During an outage a saved *server* provider is unusable, so we move to an
  /// on-device plugin and park the original id, restoring it the moment the
  /// backend answers again. A deliberate pick made during the outage clears
  /// the parked id (see [_onSelect]) and therefore sticks.
  Future<String> _resolveAndPersistProvider(
    List<ProviderEntity> providers, {
    required bool offline,
  }) async {
    final savedId = hiveService.getCurrentProvider();
    // A catalogue is not in the provider list and never will be — it is the
    // backend's view of what exists, not a source. Left alone here, or every
    // reload would fall through to "first provider" and quietly undo the
    // choice.
    if (Catalogue.isId(savedId)) return savedId;
    final saved = providers.where((p) => p.id == savedId).firstOrNull;

    if (!offline) {
      final parked = hiveService.getPreOutageProvider();
      if (parked.isNotEmpty) {
        await hiveService.clearPreOutageProvider();
        if (providers.any((p) => p.id == parked)) {
          if (parked != savedId) await hiveService.saveCurrentProvider(parked);
          return parked;
        }
      }
      if (saved != null) return saved.id;

      // The saved source is not in the list. That is NOT proof the user's
      // choice is gone: `providers` is the backend's list plus whatever the
      // four on-device hosts managed to enumerate on this launch, and each of
      // those helpers ends in `catch (_) {}` and contributes nothing when the
      // platform channel is not ready yet, the host process restarted, or the
      // extension store had not finished loading. This branch used to write
      // `providers.first.id` — vidapi — straight over the saved id, so one
      // unlucky cold start silently and PERMANENTLY moved somebody off their
      // CloudStream or Aniyomi source onto VidAPI, with nothing to say it had
      // happened and no way back but finding the source again by hand.
      //
      // So it parks the id first, exactly as the outage branch below does. The
      // fallback still takes effect for this session — the interceptor and
      // everything else read the current provider straight out of Hive, so
      // leaving those disagreeing with this bloc would be its own bug — but
      // the restore block at the top of this branch puts the user back on
      // their own source the moment the host enumerates again. A deliberate
      // pick meanwhile clears the parked id (see [_onSelect]) and sticks.
      if (savedId.isNotEmpty && hiveService.getPreOutageProvider().isEmpty) {
        await hiveService.savePreOutageProvider(savedId);
      }
      final fallback = providers.first.id;
      await hiveService.saveCurrentProvider(fallback);
      return fallback;
    }

    if (saved != null && saved.isServerIndependent) return saved.id;

    final local = providers.where((p) => p.isServerIndependent).firstOrNull;
    // Nothing local to fall back to — leave the saved id alone so the picker's
    // offline state is what the user sees, not a silent switch.
    if (local == null) return saved?.id ?? providers.first.id;

    if (savedId.isNotEmpty && hiveService.getPreOutageProvider().isEmpty) {
      await hiveService.savePreOutageProvider(savedId);
    }
    await hiveService.saveCurrentProvider(local.id);
    return local.id;
  }
}
