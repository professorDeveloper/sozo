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
      haptic: true,
      borderRadius: 10,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: desktop ? 6 : 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: desktop ? 176 : 124,
            height: desktop ? 84 : 68,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF242426), Color(0xFF151517)],
                    ),
                  ),
                ),
                HomeNetworkImage(
                  url: genre.image,
                  borderRadius: BorderRadius.zero,
                  placeholderIcon: Icons.category_outlined,
                ),
                // Black, not the accent.
                //
                // The scrim used to lean onto AppColors.primaryDark as it
                // deepened, so a row of genres carried a red wash over whatever
                // the artwork actually was — and the search grid did the same
                // thing in nine other hues. A tint keyed on nothing is noise
                // dressed as information, and over a photograph it leaves the
                // card neither the artwork's colour nor the app's. The covers
                // supply the colour; this only has to make the name readable.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x00000000),
                        Color(0x80000000),
                        Color(0xE6000000),
                      ],
                      stops: [0, 0.5, 1],
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: desktop ? 12 : 9,
                  end: desktop ? 12 : 9,
                  bottom: desktop ? 9 : 7,
                  child: Text(
                    _label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: desktop ? 14 : 12,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                      letterSpacing: -0.2,
                      shadows: const [
                        Shadow(color: Colors.black87, blurRadius: 6),
                      ],
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
