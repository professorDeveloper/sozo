import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_state.dart';
import 'package:soplay/features/extensions/data/source_installer.dart';
import 'package:soplay/features/extensions/data/extension_repo_defaults.dart';
import 'package:soplay/features/extensions/data/mangayomi_runtime.dart';
import 'package:soplay/features/profile/presentation/pages/sources_page.dart';

import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/extensions/source_language.dart' as srclang;
import 'package:soplay/core/manga/manga_channel.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/extensions/data/catalog_repository.dart';
import 'package:soplay/features/extensions/data/mangayomi_repo_store.dart';
import 'package:soplay/features/extensions/domain/entities/catalog_source_entity.dart';
import 'package:soplay/features/extensions/domain/entities/extension_repo_entity.dart';

/// Find a source by content and language, then install its required extension.
class SourceCatalogPage extends StatefulWidget {
  const SourceCatalogPage({
    super.key,
    this.initialItemType,
    this.embedded = false,
  });

  final CatalogItemType? initialItemType;

  /// Drops the Scaffold and the app bar, leaving the body to be placed inside
  /// something else.
  ///
  /// The source hub shows this as its "Add" level rather than pushing it as a
  /// route, and two app bars stacked inside one screen is not a screen. Its
  /// own title and its repositories button are the hub's when it is embedded.
  final bool embedded;

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const SourceCatalogPage()));

  @override
  State<SourceCatalogPage> createState() => _SourceCatalogPageState();
}

class _SourceCatalogPageState extends State<SourceCatalogPage> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  late List<String> _languages;
  List<CatalogLanguage> _facets = const [];
  final Map<CatalogItemType?, Future<List<CatalogLanguage>>> _facetRequests =
      {};
  final List<CatalogSourceEntity> _items = [];

  CatalogItemType? _itemType;
  String _query = '';
  Timer? _searchDebounce;

  int _page = 1;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String? _installing;
  bool _pageFailed = false;
  final Set<String> _added = {};

  bool _supported(CatalogSourceEntity source) => switch (source.kind) {
    ExtensionRepoKind.cloudstream => CloudStreamChannel.isSupported,
    ExtensionRepoKind.aniyomi => AniyomiChannel.isSupported,
    ExtensionRepoKind.manga => MangaChannel.isSupported,
    ExtensionRepoKind.mangayomi =>
      source.jsRuntime && MangayomiRuntime.isSupported,
  };

  ProviderEntity? _installed(CatalogSourceEntity source) {
    final state = context.read<ProviderBloc>().state;
    if (state is! ProviderLoaded) return null;
    final prefix = switch (source.kind) {
      ExtensionRepoKind.cloudstream => 'cs:',
      ExtensionRepoKind.aniyomi => 'an:',
      ExtensionRepoKind.manga => 'mn:',
      ExtensionRepoKind.mangayomi => 'my:',
    };
    for (final provider in state.providers) {
      if (!provider.id.startsWith(prefix)) continue;
      if (source.externalId.isNotEmpty &&
          provider.id == '$prefix${source.externalId}') {
        return provider;
      }
      if (provider.name == source.name &&
          provider.lang.toLowerCase() == source.lang.toLowerCase()) {
        return provider;
      }
    }
    return null;
  }

  /// True while a [_use] is running, so a second tap cannot start another.
  ///
  /// The Hive write is awaited BEFORE the pop, so on a slow device two taps
  /// both got past the await and both called `Navigator.pop` — the first
  /// closing this page and the second closing whatever was underneath it. The
  /// user ends up two screens back from where one tap would have left them.
  bool _using = false;

  Future<void> _use(ProviderEntity source) async {
    if (_using) return;
    _using = true;
    try {
      await getIt<HiveService>().setContentMode(source.id.contentMode.id);
      if (!mounted) return;
      context.read<ProviderBloc>().add(ProviderSelect(source.id));
      Navigator.of(context).pop();
    } finally {
      _using = false;
    }
  }

  void _manage() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const SourcesPage()));

  @override
  void initState() {
    super.initState();
    _itemType = widget.initialItemType;
    _languages = getIt<HiveService>().getProviderLanguages();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading || _pageFailed) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 600) _loadMore();
  }

  CatalogRepository get _repo => getIt<CatalogRepository>();

  /// Bumped by every fresh [_load]. A filter change, a keystroke and the
  /// language chips all start one, and without a ticket the slowest answer
  /// won: typing "anim" and then "anime" could leave the list showing "anim",
  /// and a page fetched for the old filter could be appended to the new one.
  int _generation = 0;

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
      _page = 1;
      _pageFailed = false;
    });
    try {
      // Facets are auxiliary: a slow language request must not block reading.
      unawaited(_loadFacets());
      final page = await _repo.sources(
        languages: _languages,
        itemType: _itemType,
        query: _query,
        runnableOnly: true,
        page: 1,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _loadFacets() async {
    final type = _itemType;
    final request = _facetRequests.putIfAbsent(
      type,
      () => _repo.languages(itemType: type, runnableOnly: true),
    );
    try {
      final facets = await request;
      if (mounted && type == _itemType) setState(() => _facets = facets);
    } catch (_) {
      _facetRequests.remove(type);
      if (mounted && type == _itemType) setState(() => _facets = const []);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading) return;
    final generation = _generation;
    setState(() {
      _loadingMore = true;
      _pageFailed = false;
    });
    try {
      final next = await _repo.sources(
        languages: _languages,
        itemType: _itemType,
        query: _query,
        runnableOnly: true,
        page: _page + 1,
      );
      // A page of the previous filter's results must not land under the new
      // filter's first page.
      if (!mounted || generation != _generation) return;
      setState(() {
        _page = next.page;
        _hasMore = next.hasMore;
        _items.addAll(next.items);
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      // A failed page is not a failed screen — what already loaded stays.
      setState(() {
        _loadingMore = false;
        _pageFailed = true;
      });
    }
  }

  Future<void> _toggleLanguage(String code) async {
    final next = code == 'all' ? <String>[] : List<String>.from(_languages);
    if (code != 'all' && next.remove(code) == false) next.add(code);
    // Shared with the provider picker's own row. Picking French here means
    // French there too — it is one statement about the user, not two settings
    // that can disagree.
    // Paint the choice immediately; disk/network latency is not tap feedback.
    setState(() => _languages = next);
    unawaited(_load());
    try {
      await getIt<HiveService>().setProviderLanguages(next);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('general.error'.tr())));
    }
  }

  Future<void> _install(CatalogSourceEntity source) async {
    if (_installing != null) return;
    setState(() => _installing = source.id);
    String message;
    try {
      final count = await installCatalogSource(
        source,
        getIt<MangayomiRepoStore>(),
      );
      if (count > 0 && mounted) {
        _added.add(source.id);
        context.read<ProviderBloc>().add(const ProviderLoad(localOnly: true));
      }
      message = count > 0
          ? 'catalog.installed'.tr(args: ['$count', source.repoName])
          : 'catalog.install_empty'.tr();
    } catch (e) {
      message = 'catalog.install_failed'.tr(args: ['$e']);
    }
    if (!mounted) return;
    setState(() => _installing = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _catalogBody();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        // Not 'manga.add_source'. The page was called "Add source" and every
        // row on it carried a button called "Add source" — the same key — so
        // the title said nothing about what the list was and the screen read
        // as eight identical calls to action. The title names the list; the
        // rows name the act.
        title: Text('source_manager.catalog_title'.tr()),
        actions: [
          IconButton(
            onPressed: _manage,
            icon: const Icon(Icons.more_horiz),
            tooltip: 'source_manager.manage_repositories'.tr(),
          ),
        ],
      ),
      body: _catalogBody(),
    );
  }

  /// Everything below the app bar, so the hub can host it without one.
  Widget _catalogBody() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: TextField(
            controller: _searchController,
            onChanged: (v) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 350), () {
                if (!mounted) return;
                setState(() => _query = v.trim());
                _load();
              });
            },
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'general.search'.tr(),
              hintStyle: const TextStyle(color: AppColors.textHint),
              prefixIcon: const Icon(Icons.search, color: AppColors.textHint),
              isDense: true,
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        _TypeFilterRow(
          selected: _itemType,
          onSelected: (t) {
            if (_itemType == t) return;
            setState(() => _itemType = t);
            _load();
          },
        ),
        const SizedBox(height: 6),
        if (_facets.isNotEmpty)
          _CatalogLanguageRow(
            facets: _facets,
            selected: _languages,
            onToggle: _toggleLanguage,
          ),
        const SizedBox(height: 4),
        Expanded(
          child: BlocBuilder<ProviderBloc, ProviderState>(
            builder: (_, _) => _body(),
          ),
        ),
      ],
    );
  }

  Widget _recommended() {
    final sources = <CatalogSourceEntity>[];
    for (final repo in ExtensionRepoDefaults.all) {
      if (repo.kind == ExtensionRepoKind.cloudstream) continue;
      final type = _itemType;
      if (type == CatalogItemType.novel && repo.novelUrl == null) continue;
      if (type == CatalogItemType.manga &&
          repo.kind == ExtensionRepoKind.aniyomi) {
        continue;
      }
      if ((type == CatalogItemType.anime || type == CatalogItemType.video) &&
          (repo.kind == ExtensionRepoKind.manga ||
              (repo.kind == ExtensionRepoKind.mangayomi &&
                  repo.animeUrl == null))) {
        continue;
      }
      final source = CatalogSourceEntity(
        id: '${repo.kind.name}:${repo.url}:${type?.name}',
        kind: repo.kind,
        name: repo.name,
        repoName: repo.name,
        repoUrl: repo.url,
        itemType: type == CatalogItemType.video
            ? CatalogItemType.anime
            : type ?? CatalogItemType.manga,
      );
      if (_supported(source)) sources.add(source);
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: sources.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('source_manager.recommended_repositories'.tr()),
          );
        }
        final source = sources[i - 1];
        return ListTile(
          title: Text(source.name),
          subtitle: Text(
            source.kind == ExtensionRepoKind.mangayomi
                ? 'Mangayomi'
                : source.kind.name,
          ),
          trailing: _installing == source.id
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton(
                  onPressed: _installing != null || _added.contains(source.id)
                      ? null
                      : () => _install(source),
                  child: Text(
                    _added.contains(source.id)
                        ? 'source_manager.added'.tr()
                        : 'source_manager.add_short'.tr(),
                  ),
                ),
        );
      },
    );
  }

  Widget _body() {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return Column(
        children: [
          SizedBox(
            height: 190,
            child: _CatalogError(message: _error!, onRetry: _load),
          ),
          Expanded(child: _recommended()),
          TextButton.icon(
            onPressed: _manage,
            icon: const Icon(Icons.add),
            label: Text('source_manager.manage_repositories'.tr()),
          ),
          const SizedBox(height: 24),
        ],
      );
    }
    if (_items.isEmpty) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'catalog.empty'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textHint, fontSize: 13),
            ),
          ),
          Expanded(child: _recommended()),
        ],
      );
    }
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        if (i >= _items.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: _loadingMore
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(
                      onPressed: _loadMore,
                      child: Text(
                        _pageFailed
                            ? 'general.retry'.tr()
                            : 'source_manager.load_more'.tr(),
                      ),
                    ),
            ),
          );
        }
        final s = _items[i];
        final installed = _installed(s);
        return _CatalogTile(
          source: s,
          installable:
              _supported(s) && (_installing == null || _installing == s.id),
          label: installed != null
              ? 'source_manager.use_short'.tr()
              : _added.contains(s.id)
              ? 'source_manager.added'.tr()
              : 'source_manager.add_short'.tr(),
          busy: _installing == s.id,
          onInstall: installed != null
              ? () => _use(installed)
              : _added.contains(s.id)
              ? null
              : () => _install(s),
        );
      },
    );
  }
}

/// Anime / video / manga / novel. Kept next to the language row because the two
/// questions a user actually arrives with are "what can I read" and "in what".
class _TypeFilterRow extends StatelessWidget {
  const _TypeFilterRow({required this.selected, required this.onSelected});

  final CatalogItemType? selected;
  final ValueChanged<CatalogItemType?> onSelected;

  static const _options = <(CatalogItemType?, String)>[
    (null, 'catalog.type_all'),
    (CatalogItemType.anime, 'catalog.type_anime'),
    (CatalogItemType.video, 'catalog.type_video'),
    (CatalogItemType.manga, 'catalog.type_manga'),
    (CatalogItemType.novel, 'catalog.type_novel'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final (type, key) = _options[i];
          final active = type == selected;
          return GestureDetector(
            onTap: () => onSelected(type),
            child: AnimatedContainer(
              duration: Duration(
                milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 120,
              ),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: active
                      ? AppColors.primary.withValues(alpha: 0.55)
                      : Colors.white.withValues(alpha: 0.07),
                ),
              ),
              child: Text(
                key.tr(),
                style: TextStyle(
                  color: active ? Colors.white : AppColors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The catalog's language chips.
///
/// Counts come from the server's own facet over the whole catalog, not from the
/// page on screen — a page is fifty rows out of thousands, and a filter built
/// from an arbitrary slice would show numbers that change as you scroll.
class _CatalogLanguageRow extends StatelessWidget {
  const _CatalogLanguageRow({
    required this.facets,
    required this.selected,
    required this.onToggle,
  });

  final List<CatalogLanguage> facets;
  final List<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final ordered = srclang.orderedLanguages(
      facets.map((f) => f.lang),
      selected,
    );
    final byCode = {for (final f in facets) f.lang: f};
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: ordered.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final code = ordered[i];
          final facet = byCode[code];
          final active = code == 'all'
              ? selected.isEmpty
              : selected.any((c) => srclang.normalizeLang(c) == code);
          return GestureDetector(
            onTap: () => onToggle(code),
            child: AnimatedContainer(
              duration: Duration(
                milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 120,
              ),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: active
                      ? AppColors.primary.withValues(alpha: 0.55)
                      : Colors.white.withValues(alpha: 0.07),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    srclang.labelFor(code),
                    style: TextStyle(
                      color: active ? Colors.white : AppColors.textSecondary,
                      fontSize: 12.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  if (facet != null) ...[
                    const SizedBox(width: 5),
                    Text(
                      '${facet.count}',
                      style: TextStyle(
                        color: active
                            ? AppColors.primaryLight.withValues(alpha: 0.75)
                            : AppColors.textHint,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CatalogTile extends StatelessWidget {
  const _CatalogTile({
    required this.source,
    required this.installable,
    required this.busy,
    required this.onInstall,
    required this.label,
  });

  final CatalogSourceEntity source;
  final bool installable;
  final bool busy;
  final VoidCallback? onInstall;
  final String label;

  static const _kindLabels = {
    ExtensionRepoKind.cloudstream: 'CloudStream',
    ExtensionRepoKind.aniyomi: 'Aniyomi',
    ExtensionRepoKind.manga: 'Manga',
    ExtensionRepoKind.mangayomi: 'Mangayomi',
  };

  @override
  Widget build(BuildContext context) {
    return Opacity(
      // Dimmed, not hidden. A source this platform cannot run is the reason the
      // list is shorter here than on a phone, and that is worth being able to
      // see rather than inferring from an unexplained gap.
      opacity: installable ? 1 : 0.45,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 11, 10, 11),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          source.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (source.verified) ...[
                        const SizedBox(width: 5),
                        const Icon(
                          Icons.verified_rounded,
                          size: 14,
                          color: Color(0xFF34A853),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (source.lang.isNotEmpty)
                        srclang.shortLabelFor(source.lang),
                      _kindLabels[source.kind] ?? '',
                      source.repoName,
                      if (!installable)
                        source.kind == ExtensionRepoKind.mangayomi
                            ? 'catalog.needs_js'.tr()
                            : 'catalog.android_only'.tr(),
                    ].where((s) => s.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              TextButton(
                onPressed: installable ? onInstall : null,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  foregroundColor: AppColors.primaryLight,
                ),
                child: Text(label),
              ),
          ],
        ),
      ),
    );
  }
}

class _CatalogError extends StatelessWidget {
  const _CatalogError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'catalog.unreachable'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textHint, fontSize: 11.5),
            ),
            const SizedBox(height: 14),
            TextButton(onPressed: onRetry, child: Text('general.retry'.tr())),
          ],
        ),
      ),
    );
  }
}
