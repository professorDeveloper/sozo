import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';
import 'package:soplay/features/download/domain/entities/download_status.dart';
import 'package:soplay/features/download/domain/usecases/get_downloads_usecase.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/features/manga/domain/entities/reader_args.dart';

class DownloadsSection extends StatefulWidget {
  const DownloadsSection({super.key});

  @override
  State<DownloadsSection> createState() => _DownloadsSectionState();
}

class _DownloadsSectionState extends State<DownloadsSection> {
  final GetDownloadsUseCase _downloads = getIt<GetDownloadsUseCase>();
  List<DownloadItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _downloads.revision.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _downloads.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    final all = _downloads();
    setState(
      () => _items = all
          .where((i) => i.status == DownloadStatus.completed)
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Padding inside the InkWell — outside it the tap target was only as
          // tall as the title text.
          HomeSectionTapTarget(
            onTap: () => context.push('/downloads'),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(17, 18, 20, 14),
              child: Row(
                children: [
                  const Icon(
                    Icons.download_done_rounded,
                    color: AppColors.textSecondary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'home.downloaded'.tr(),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textHint,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 170,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _items.length > 20 ? 20 : _items.length,
              itemBuilder: (_, i) => _DownloadCard(item: _items[i], siblings: _items),
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadCard extends StatelessWidget {
  const _DownloadCard({required this.item, required this.siblings});

  final DownloadItem item;
  final List<DownloadItem> siblings;

  /// Read-only access to the library, so the card can resolve a poster and a
  /// playable path without knowing where either lives on this device.
  GetDownloadsUseCase get downloads => getIt<GetDownloadsUseCase>();

  void _open(BuildContext context) {
    if (item.isManga) {
      final group =
          siblings
              .where((d) => d.isManga && d.contentUrl == item.contentUrl)
              .toList()
            ..sort(
              (a, b) => (a.chapterIndex ?? 0).compareTo(b.chapterIndex ?? 0),
            );
      final chapters = group
          .map(
            (d) => EpisodeEntity(
              episode: d.episodeNumber ?? 0,
              label: d.episodeLabel ?? d.title,
              mediaRef: d.chapterRef ?? '',
            ),
          )
          .toList();
      var start = group.indexWhere((d) => d.id == item.id);
      if (start < 0) start = 0;
      context.push(
        '/reader',
        extra: ReaderArgs(
          title: item.title,
          provider: item.provider,
          contentUrl: item.contentUrl,
          thumbnail: downloads.thumbnailOf(item) ?? item.thumbnailUrl,
          chapters: chapters,
          initialChapterIndex: start,
        ),
      );
      return;
    }
    // Asked for, not assumed. A row can still say "downloaded" for a file that
    // has gone — an SD card pulled, a cleaner app — and the honest answer is to
    // say so and send the viewer to the screen that can fix it.
    final path = downloads.pathOf(item);
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('downloads.file_missing_retry'.tr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.push('/downloads');
      return;
    }
    context.push(
      '/player',
      extra: PlayerArgs(
        title: item.isSerial && item.episodeNumber != null
            ? '${item.title} · ${'home.ep_number'.tr(args: ['${item.episodeNumber}'])}'
            : item.title,
        provider: item.provider,
        headers: const {},
        contentUrl: item.contentUrl,
        thumbnail: downloads.thumbnailOf(item) ?? item.thumbnailUrl,
        movieUrl: item.isHls ? Uri.file(path).toString() : path,
        type: item.isHls ? 'hls' : null,
        showDownloadAction: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return HoverTap(
      onTap: () => _open(context),
      child: SizedBox(
        width: 150,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      HomeNetworkImage(
                        url: downloads.thumbnailOf(item) ?? item.thumbnailUrl,
                        borderRadius: BorderRadius.zero,
                        placeholderIcon: item.isManga
                            ? Icons.menu_book_outlined
                            : Icons.movie_outlined,
                      ),
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            item.isManga
                                ? Icons.menu_book_rounded
                                : Icons.download_done_rounded,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                      ),
                      if (item.isSerial && item.episodeNumber != null)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              'home.ep_number'.tr(
                                args: ['${item.episodeNumber}'],
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
