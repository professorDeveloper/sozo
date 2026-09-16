import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/features/detail/domain/services/alternate_source_service.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/search/domain/entities/cross_search_result.dart';

/// "That is not the right show — let me find it myself."
///
/// One source, one query, and that source's answer in its own order. The
/// matcher that fills the switcher is right most of the time and wrong the rest
/// of it, and no threshold fixes the rest: a source may carry the show under
/// its romaji, under the dub's name, or split across season titles that share
/// no distinctive word with the one the catalogue uses. The person looking at
/// both titles can settle it in a second, and this is where they do.
///
/// Nothing here is ranked or filtered. [AlternateSourceService.searchOne] hands
/// back the whole leg exactly as the source answered it, because the viewer is
/// typing their own query — telling them their own search missed would be the
/// same mistake the automatic matcher just made, with more confidence.
///
/// Returns the entry they picked, or null if they backed out.
class SourceSearchSheet extends StatefulWidget {
  const SourceSearchSheet({
    super.key,
    required this.provider,
    required this.query,
    this.candidates,
  });

  /// The one source being asked. Its name is the title of the sheet, because
  /// "no results" means something quite different per source.
  final ProviderRef provider;

  /// What the field starts with: the title we were looking for. Pre-filled
  /// rather than blank so the common correction — the source spells it almost
  /// the same — is one tap and an edit, not a retype.
  final String query;

  /// The installed sources, when the caller has them. Passed through so a
  /// source that exists only on this device can be searched at all; without it
  /// the service falls back to the backend's list, which does not know about
  /// extensions.
  final List<ProviderEntity>? candidates;

  static Future<MovieEntity?> show(
    BuildContext context, {
    required ProviderRef provider,
    required String query,
    List<ProviderEntity>? candidates,
  }) {
    return showAdaptiveModal<MovieEntity>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SourceSearchSheet(
        provider: provider,
        query: query,
        candidates: candidates,
      ),
    );
  }

  @override
  State<SourceSearchSheet> createState() => _SourceSearchSheetState();
}

class _SourceSearchSheetState extends State<SourceSearchSheet> {
  late final TextEditingController _field = TextEditingController(
    text: widget.query,
  );

  bool _searching = false;
  ProviderSearchResult? _result;

  /// Which query [_result] answers.
  ///
  /// The field can be edited while a leg is in flight — an extension host is
  /// given forty-five seconds — and without this the rows under a freshly typed
  /// query are silently the previous one's.
  String _answered = '';

  @override
  void initState() {
    super.initState();
    _run(widget.query);
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _run(String query) async {
    final text = query.trim();
    if (text.isEmpty || _searching) return;
    setState(() {
      _searching = true;
      _result = null;
    });
    final result = await getIt<AlternateSourceService>().searchOne(
      providerId: widget.provider.id,
      query: text,
      candidates: widget.candidates,
    );
    if (!mounted) return;
    setState(() {
      _searching = false;
      _answered = text;
      _result = result;
    });
  }

  /// What to say when there are no rows to show.
  ///
  /// A source that timed out and a source that honestly has nothing look
  /// identical in a list of zero results, and they call for opposite things:
  /// try again, versus try a different name. [ProviderSearchResult.status] is
  /// carried here precisely so the two can be told apart.
  String _emptyMessage() {
    final result = _result;
    if (result == null) {
      return 'player.src_search_unavailable'.tr(args: [widget.provider.name]);
    }
    return switch (result.status) {
      ProviderSearchStatus.ok ||
      ProviderSearchStatus.empty => 'player.src_search_empty'.tr(
        args: [widget.provider.name, _answered],
      ),
      ProviderSearchStatus.timeout => 'player.src_search_slow'.tr(
        args: [widget.provider.name],
      ),
      ProviderSearchStatus.error => 'player.src_search_failed'.tr(
        args: [widget.provider.name],
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final items = _result?.items ?? const <MovieEntity>[];
    return SafeArea(
      child: Padding(
        // The field is the point of the sheet, so it has to sit above the
        // keyboard rather than behind it.
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.manage_search_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'player.src_search_title'.tr(
                        args: [widget.provider.name],
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (_searching)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white54,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: _field,
                autofocus: false,
                textInputAction: TextInputAction.search,
                onSubmitted: _run,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'player.src_search_hint'.tr(),
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white10,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    // 48dp, like every other one-tap action in the switcher:
                    // this is the button somebody reaches for after editing the
                    // name, and a small one is a missed tap on a phone.
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    tooltip: 'player.src_search_go'.tr(),
                    onPressed: () => _run(_field.text),
                    icon: const Icon(
                      Icons.search_rounded,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            Flexible(
              child: items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 28,
                      ),
                      child: Text(
                        _searching
                            ? 'player.src_searching'.tr(
                                args: [widget.provider.name],
                              )
                            : _emptyMessage(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final item = items[i];
                        return ListTile(
                          dense: true,
                          onTap: () => Navigator.of(context).pop(item),
                          leading: const Icon(
                            Icons.check_circle_outline_rounded,
                            color: Colors.white54,
                            size: 20,
                          ),
                          title: Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: item.year != null
                              ? Text(
                                  '${item.year}',
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 12,
                                  ),
                                )
                              : null,
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
