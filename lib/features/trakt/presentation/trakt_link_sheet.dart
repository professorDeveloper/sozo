import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';
import 'package:soplay/features/trakt/data/trakt_api.dart';
import 'package:soplay/features/trakt/data/trakt_link_store.dart';
import 'package:soplay/features/trakt/data/trakt_service.dart';
import 'package:soplay/features/trakt/data/trakt_tracker.dart';
import 'package:soplay/features/trakt/presentation/trakt_brand.dart';

/// Ties a title on a source to the right film or show on Trakt, by hand.
///
/// The automatic match takes only an exact, single hit, so a title a source
/// names its own way — or a remake — is left unmatched and nothing reaches
/// Trakt. This is the way to say which one it is; a choice made here is
/// never replaced by a later guess.
class TraktLinkSheet extends StatefulWidget {
  const TraktLinkSheet({
    super.key,
    required this.provider,
    required this.contentUrl,
    required this.title,
    required this.isSerial,
  });

  final String provider;
  final String contentUrl;
  final String title;
  final bool isSerial;

  /// Resolves to the link saved, or null when the sheet was closed.
  static Future<TraktLink?> show(
    BuildContext context, {
    required String provider,
    required String contentUrl,
    required String title,
    required bool isSerial,
  }) => showAdaptiveModal<TraktLink>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => TraktLinkSheet(
      provider: provider,
      contentUrl: contentUrl,
      title: title,
      isSerial: isSerial,
    ),
  );

  @override
  State<TraktLinkSheet> createState() => _TraktLinkSheetState();
}

class _TraktLinkSheetState extends State<TraktLinkSheet> {
  final TraktService _service = getIt<TraktService>();
  late final TextEditingController _query = TextEditingController(
    text: TraktTracker.baseTitle(widget.title),
  );
  late String _kind = widget.isSerial ? 'show' : 'movie';
  late int? _season = TraktTracker.seasonIn(widget.title);
  List<TraktMedia> _results = const [];
  bool _loading = false;
  String? _error;
  Timer? _debounce;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQuery(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 380), _search);
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    final clientId = _service.clientId;
    if (q.length < 2 || clientId == null) return;
    final gen = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final found = await _service.api.search(
        q,
        clientId: clientId,
        kind: _kind,
      );
      if (!mounted || gen != _generation) return;
      setState(() => _results = found);
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() => _error = e is TraktException ? e.message : '$e');
    } finally {
      if (mounted && gen == _generation) setState(() => _loading = false);
    }
  }

  Future<void> _pick(TraktMedia m) async {
    final link = TraktLink(
      provider: widget.provider,
      contentUrl: widget.contentUrl,
      traktId: m.traktId,
      kind: m.kind,
      title: m.title,
      year: m.year,
      season: m.isMovie ? null : _season,
    );
    await _service.links.save(link);
    unawaited(_service.syncLinks());
    if (mounted) Navigator.of(context).pop(link);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.78,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
                child: Row(
                  children: [
                    const TraktLogo(size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'trakt.link_title'.tr(),
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                child: Text(
                  'trakt.link_explainer'.tr(args: [widget.title]),
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: TextField(
                  controller: _query,
                  onChanged: _onQuery,
                  onSubmitted: (_) => _search(),
                  textInputAction: TextInputAction.search,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: AppColors.surfaceVariant,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
                child: Row(
                  children: [
                    for (final k in ['show', 'movie']) ...[
                      ChoiceChip(
                        label: Text(
                          k == 'show' ? 'trakt.show'.tr() : 'trakt.movie'.tr(),
                        ),
                        selected: _kind == k,
                        showCheckmark: false,
                        selectedColor: kTraktRed.withValues(alpha: 0.22),
                        side: BorderSide(
                          color: _kind == k ? kTraktRed : AppColors.border,
                          width: 0.8,
                        ),
                        onSelected: (_) {
                          setState(() => _kind = k);
                          _search();
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                    const Spacer(),
                    if (_kind == 'show')
                      _SeasonPicker(
                        value: _season,
                        onChanged: (v) => setState(() => _season = v),
                      ),
                  ],
                ),
              ),
              Expanded(child: _list()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list() {
    if (_loading && _results.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: kTraktRed),
      );
    }
    if (_error != null && _results.isEmpty) {
      return Center(
        child: AnilistStateMessage(
          icon: Icons.cloud_off_rounded,
          text: _error!,
          actionLabel: 'anilist.retry'.tr(),
          onAction: _search,
          accent: kTraktRed,
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          'trakt.link_none'.tr(),
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final m = _results[i];
        return Material(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _pick(m),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  AnilistCover(url: m.poster, width: 44, radius: 7),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          [
                            if (m.year != null) '${m.year}',
                            m.isMovie ? 'trakt.movie'.tr() : 'trakt.show'.tr(),
                          ].join(' · '),
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.link_rounded, color: kTraktRed, size: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Which season the source's episode numbers count within; "All" when the
/// source numbers the whole show from 1, as anime sources do.
class _SeasonPicker extends StatelessWidget {
  const _SeasonPicker({required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'trakt.link_season'.tr(),
      initialValue: value ?? 0,
      onSelected: (v) => onChanged(v == 0 ? null : v),
      itemBuilder: (_) => [
        PopupMenuItem(value: 0, child: Text('trakt.link_season_all'.tr())),
        for (var s = 1; s <= 30; s++)
          PopupMenuItem(
            value: s,
            child: Text('trakt.link_season_n'.tr(args: ['$s'])),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value == null
                  ? 'trakt.link_season_all'.tr()
                  : 'trakt.link_season_n'.tr(args: ['$value']),
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Icon(Icons.expand_more_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}
