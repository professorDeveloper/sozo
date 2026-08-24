import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/system/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../search/domain/entities/genre_entity.dart';
import '../../domain/entities/view_all.dart';
import 'home_shared_widgets.dart';

class GenreCard extends StatelessWidget {
  const GenreCard({super.key, required this.genre});

  final GenreEntity genre;

  String get _label {
    if (genre.name.isNotEmpty) return genre.name;
    return genre.slug
        .replaceAll('-', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktopPlatform;
    return HoverTap(
      onTap: () => context.push(
        '/view-all',
        extra: ViewAllEntity(type: 'genre', slug: genre.slug, name: _label),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: desktop ? 7 : 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(desktop ? 12 : 10),
          child: SizedBox(
            width: desktop ? 190 : 110,
            height: desktop ? 90 : 72,
            child: Stack(
              fit: StackFit.expand,
              children: [
                HomeNetworkImage(
                  url: genre.image,
                  borderRadius: BorderRadius.zero,
                  placeholderIcon: Icons.category_outlined,
                ),
                // The scrim leans onto the accent as it deepens, so a wall of
                // genre thumbnails carries the chosen colour instead of being
                // twelve identical black fades.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.18),
                        AppColors.primaryDark.withValues(alpha: 0.30),
                        Colors.black.withValues(alpha: 0.78),
                      ],
                      stops: const [0, 0.55, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(height: 2.5, color: AppColors.primary),
                ),
                Positioned(
                  left: desktop ? 12 : 8,
                  right: desktop ? 12 : 8,
                  bottom: desktop ? 10 : 7,
                  child: Text(
                    _label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: desktop ? 15 : 11,
                      fontWeight: desktop ? FontWeight.w800 : FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
