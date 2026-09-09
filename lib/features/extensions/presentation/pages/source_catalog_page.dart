import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

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

/// Browse every source the harvester has seen, across all four ecosystems, by
/// language.
///
/// ## The question this exists to answer
///
/// The sources pages let a user add a *repo*. What was in one could only be
/// learned by adding it: a French user was told to install a 300-source anime
/// repo on the chance that some of it was French. Fifteen entries were. Nothing
/// in the app could say so before the install, because saying so means parsing
/// every index of every repo — which is what the backend now does on a schedule.
///
/// ## One tap installs a repo, not a source
///
/// There is no such thing as installing one source: every ecosystem's unit of
/// installation is the repo. Tapping a row adds the repo that carries it, and
/// the source then shows up in the provider picker with everything else that
/// arrived alongside. The sheet says so rather than letting the extra hundred
/// sources be a surprise.
class SourceCatalogPage extends StatefulWidget {
  const SourceCatalogPage({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SourceCatalogPage()),
      );

  @override
  State<SourceCatalogPage> createState() => _SourceCatalogPageState();
}

class _SourceCatalogPageState extends State<SourceCatalogPage> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  late List<String> _languages;
  List<CatalogLanguage> _facets = const [];
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

  /// Only ever true on Android, where the three Kotlin hosts exist. Off it, a
  /// row that cannot be installed is still worth *seeing* — it is why the app
  /// has fewer sources on iOS, and hiding it makes that look like an empty
  /// catalog instead of a platform limit.
  bool get _android => !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
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
    if (!_hasMore || _loadingMore || _loading) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 600) _loadMore();
  }

  CatalogRepository get _repo => getIt<CatalogRepository>();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
    });
    try {
      final results = await Future.wait([
        _repo.sources(
          languages: _languages,
          itemType: _itemType,
          query: _query,
          page: 1,
        ),
        _repo.languages(itemType: _itemType),
      ]);
      if (!mounted) return;
      final page = results[0] as CatalogPage;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _hasMore = page.hasMore;
        _facets = results[1] as List<CatalogLanguage>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // No compiled-in fallback on purpose: the catalog IS the backend's
      // answer, and a stale snapshot of somebody else's repos presented as
      // current is worse than saying the server could not be reached.
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final next = await _repo.sources(
        languages: _languages,
        itemType: _itemType,
        query: _query,
        page: _page + 1,
      );
      if (!mounted) return;
      setState(() {
        _page = next.page;
        _hasMore = next.hasMore;
        _items.addAll(next.items);
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      // A failed page is not a failed screen — what already loaded stays.
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _toggleLanguage(String code) async {
    final next = List<String>.from(_languages);
    if (next.remove(code) == false) next.add(code);
    // Shared with the provider picker's own row. Picking French here means
    // French there too — it is one statement about the user, not two settings
    // that can disagree.
    await getIt<HiveService>().setProviderLanguages(next);
    if (!mounted) return;
    setState(() => _languages = next);
    await _load();
  }

  Future<void> _install(CatalogSourceEntity source) async {
    if (_installing != null) return;
    setState(() => _installing = source.id);
    String message;
    try {
      final added = switch (source.kind) {
        ExtensionRepoKind.cloudstream =>
          (await CloudStreamChannel.addRepo(source.repoUrl))['pluginCount'],
        ExtensionRepoKind.aniyomi =>
          (await AniyomiChannel.addRepo(source.repoUrl))['sourceCount'],
        ExtensionRepoKind.manga =>
          (await MangaChannel.addRepo(source.repoUrl))['sourceCount'],
        ExtensionRepoKind.mangayomi =>
          (await getIt<MangayomiRepoStore>().addRepo(source.repoUrl))['added'],
      };
      final count = (added as num?)?.toInt() ?? 0;
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Text('catalog.title'.tr()),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: TextField(
              controller: _searchController,
              onChanged: (v) {
                _searchDebounce?.cancel();
                _searchDebounce = Timer(
                  const Duration(milliseconds: 350),
                  () {
                    if (!mounted) return;
                    setState(() => _query = v.trim());
                    _load();
                  },
                );
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
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return _CatalogError(message: _error!, onRetry: _load);
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'catalog.empty'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textHint, fontSize: 13),
          ),
        ),
      );
    }
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        if (i >= _items.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final s = _items[i];
        return _CatalogTile(
          source: s,
          installable: s.installableOn(android: _android),
          busy: _installing == s.id,
          onInstall: () => _install(s),
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
      height: 34,
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
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active
                    ? AppColors.primary.withValues(alpha: 0.18)
                    : AppColors.surface,
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
                  color: active ? AppColors.primaryLight : AppColors.textSecondary,
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
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: ordered.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final code = ordered[i];
          final facet = byCode[code];
          final active =
              selected.any((c) => srclang.normalizeLang(c) == code);
          return GestureDetector(
            onTap: () => onToggle(code),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active
                    ? AppColors.primary.withValues(alpha: 0.18)
                    : AppColors.surface,
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
                      color: active
                          ? AppColors.primaryLight
                          : AppColors.textSecondary,
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
  });

  final CatalogSourceEntity source;
  final bool installable;
  final bool busy;
  final VoidCallback onInstall;

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
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  foregroundColor: AppColors.primaryLight,
                ),
                child: Text('catalog.add_repo'.tr()),
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
            TextButton(
              onPressed: onRetry,
              child: Text('general.retry'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
