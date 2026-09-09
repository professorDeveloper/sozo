import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/search/presentation/blocs/search_bloc.dart';
import 'package:soplay/features/search/presentation/widgets/voice_search_button.dart';
import 'package:soplay/features/search/presentation/widgets/search_filter_sheet.dart';
import 'package:soplay/features/search/presentation/widgets/search_header.dart';
import 'package:soplay/features/search/presentation/widgets/search_state_views.dart';

class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) => const _SearchView();
}

class _SearchView extends StatefulWidget {
  const _SearchView();

  @override
  State<_SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<_SearchView> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _scrollController = ScrollController();
  final _blurProgress = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Coming back to the tab: the bloc still holds the last query, so the box
    // must show it instead of looking empty over a full grid of results. The
    // bloc loads itself, so re-entering the tab never clears the results.
    _controller.text = context.read<SearchBloc>().state.criteria.text;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _scrollController.dispose();
    _blurProgress.dispose();
    super.dispose();
  }

  void _onScroll() {
    final next = (_scrollController.offset / 80).clamp(0.0, 1.0);
    if ((next - _blurProgress.value).abs() >= 0.015) {
      _blurProgress.value = next;
    }

    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      context.read<SearchBloc>().add(const SearchLoadMore());
    }
  }

  void _maybeAutoFill(SearchState state) {
    if (!isDesktopPlatform) return;
    if (state.status != SearchStatus.loaded ||
        !state.hasMore ||
        state.isLoadingMore) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_scrollController.position.maxScrollExtent <= 0) {
        context.read<SearchBloc>().add(const SearchLoadMore());
      }
    });
  }

  /// Torrent streaming is Android-only — the engine is a native Android
  /// library with no iOS or desktop build. The option is hidden rather than
  /// shown and failing.
  static bool get _torrentsAvailable => !kIsWeb && Platform.isAndroid;

  void _openTorrents(String query) {
    // The query travels with it, so the torrent search opens already looking
    // for the same thing rather than making the user type it a second time.
    context.push('/torrents', extra: query);
  }

  void _clearSearch() {
    _controller.clear();
    context.read<SearchBloc>().add(const SearchQueryChanged(''));
  }

  void _runQuery(String query) {
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    context.read<SearchBloc>().add(SearchSubmitted(query));
  }

  void _openCrossSearch([String? query]) {
    final q = (query ?? _controller.text).trim();
    context.push('/cross-search', extra: q.isEmpty ? null : q);
  }

  void _openFilter() {
    final bloc = context.read<SearchBloc>();
    showAdaptiveModal<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SearchFilterSheet(
        initialSelection: SearchFilterSelection(genre: bloc.state.criteria.genre),
        genres: bloc.state.genres,
        // Always dispatch: a genre picked or cleared while text is in the box
        // used to change nothing but the button's active dot.
        onApply: (selection) => bloc.add(SearchGenreSelected(selection.genre)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final headerHeight = topPad + 128.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: BlocConsumer<SearchBloc, SearchState>(
        listener: (context, state) => _maybeAutoFill(state),
        builder: (context, state) => Stack(
          children: [
            SearchContentView(
              state: state,
              scrollController: _scrollController,
              topPad: headerHeight,
              bottomPad: bottomPad,
              onRetry: () => context.read<SearchBloc>().add(const SearchRetry()),
              onSuggestion: _runQuery,
              onGenre: (genre) =>
                  context.read<SearchBloc>().add(SearchGenreSelected(genre)),
              onRemoveRecent: (query) =>
                  context.read<SearchBloc>().add(SearchRecentRemoved(query)),
              onClearRecents: () =>
                  context.read<SearchBloc>().add(const SearchRecentsCleared()),
              onTryAllSources: () => _openCrossSearch(state.criteria.text),
              onSearchTorrents: _torrentsAvailable
                  ? () => _openTorrents(state.criteria.text)
                  : null,
            ),
            ValueListenableBuilder<double>(
              valueListenable: _blurProgress,
              builder: (context, progress, _) => SearchStickyHeader(
                progress: progress,
                topPad: topPad,
                controller: _controller,
                focus: _focus,
                hasActiveFilter: state.criteria.genre.isNotEmpty,
                showFilter: state.hasGenres,
                onFilterTap: _openFilter,
                onTorrentTap: _torrentsAvailable
                    ? () => _openTorrents(_controller.text)
                    : null,
                onMultiSearchTap: _openCrossSearch,
                onQueryChanged: (q) =>
                    context.read<SearchBloc>().add(SearchQueryChanged(q)),
                onSubmitted: (q) =>
                    context.read<SearchBloc>().add(SearchSubmitted(q)),
                onClear: _clearSearch,
                voiceButton: VoiceSearchButton(
                  // Partial results land in the field as they are heard; only
                  // the final transcript runs a search, so a half-heard title
                  // never fires a query of its own.
                  onText: (t) {
                    _controller.text = t;
                    _controller.selection =
                        TextSelection.collapsed(offset: t.length);
                    context.read<SearchBloc>().add(SearchQueryChanged(t));
                  },
                  onSubmit: _runQuery,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
