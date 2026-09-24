import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/download/domain/entities/downloaded_title.dart';
import 'package:soplay/features/download/presentation/download_messages.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';

/// The offline library as posters, one per title.
class DownloadedTitlesGrid extends StatelessWidget {
  const DownloadedTitlesGrid({
    super.key,
    required this.titles,
    required this.thumbnailOf,
    required this.providerNameOf,
    required this.onOpen,
    required this.onActions,
  });

  final List<DownloadedTitle> titles;
  final String? Function(DownloadItem) thumbnailOf;
  final String Function(DownloadedTitle) providerNameOf;
  final ValueChanged<DownloadedTitle> onOpen;
  final ValueChanged<DownloadedTitle> onActions;

  @override
  Widget build(BuildContext context) {
    final captionHeight = MediaQuery.textScalerOf(context).scale(13) * 4.4;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          const maxExtent = 150.0;
          final columns = (constraints.crossAxisExtent / maxExtent)
              .ceil()
              .clamp(2, 8);
          final tileWidth =
              (constraints.crossAxisExtent - (columns - 1) * 12) / columns;
          return SliverGrid.builder(
            itemCount: titles.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
              mainAxisExtent: tileWidth * 1.5 + 8 + captionHeight,
            ),
            itemBuilder: (_, i) => _TitleCard(
              title: titles[i],
              thumbnail: thumbnailOf(titles[i].lead),
              providerName: providerNameOf(titles[i]),
              onOpen: () => onOpen(titles[i]),
              onActions: () => onActions(titles[i]),
            ),
          );
        },
      ),
    );
  }
}

class _TitleCard extends StatelessWidget {
  const _TitleCard({
    required this.title,
    required this.thumbnail,
    required this.providerName,
    required this.onOpen,
    required this.onActions,
  });

  final DownloadedTitle title;
  final String? thumbnail;
  final String providerName;
  final VoidCallback onOpen;
  final VoidCallback onActions;

  String get _count {
    if (title.isMovie) return 'downloads.title_movie'.tr();
    return (title.isReader
            ? 'downloads.title_chapters_n'
            : 'downloads.title_episodes_n')
        .tr(args: ['${title.completed}']);
  }

  @override
  Widget build(BuildContext context) {
    final local = thumbnail;
    final placeholder = title.isReader
        ? Icons.menu_book_outlined
        : Icons.movie_outlined;
    final remote = HomeNetworkImage(
      url: title.thumbnailUrl,
      borderRadius: BorderRadius.zero,
      placeholderIcon: placeholder,
    );
    return Semantics(
      button: true,
      label: '${title.title}, $_count',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: AppColors.surface,
                    child: local != null
                        ? Image.file(
                            File(local),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => remote,
                          )
                        : remote,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.center,
                        colors: [Color(0xB3000000), Color(0x00000000)],
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    start: 8,
                    bottom: 8,
                    end: 8,
                    child: Row(
                      children: [
                        Icon(
                          Icons.download_done_rounded,
                          size: 15,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            title.sizeBytes > 0
                                ? formatBytes(title.sizeBytes)
                                : _count,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned.fill(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(onTap: onOpen, onLongPress: onActions),
                    ),
                  ),
                  PositionedDirectional(
                    top: 2,
                    end: 2,
                    child: Material(
                      color: const Color(0x66000000),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: IconButton(
                        tooltip: 'downloads.title_actions'.tr(),
                        onPressed: onActions,
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        icon: const Icon(
                          Icons.more_vert_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$_count · $providerName',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textHint, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
