import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/features/profiles/domain/household_profile.dart';

/// The avatar presets. The server stores only the id, so these ids must never
/// be renamed; an unknown id (from a newer build) falls back to the initial.
class ProfileAvatars {
  ProfileAvatars._();

  /// Illustrated avatars bundled under `assets/avatars/` (DiceBear, CC0),
  /// drawn over the profile's colour. These are what the picker offers.
  /// Each one has its own background, as on Netflix, rather than the
  /// profile's colour behind every face.
  static const Map<String, String> imageColors = {
    'lorelei-1': '#e50914',
    'lorelei-2': '#1e88e5',
    'lorelei-3': '#43a047',
    'lorelei-4': '#8e24aa',
    'lorelei-5': '#fb8c00',
    'lorelei-6': '#00acc1',
    'lorelei-7': '#d81b60',
    'lorelei-8': '#3949ab',
    'open-peeps-1': '#5c6bc0',
    'open-peeps-2': '#26a69a',
    'open-peeps-3': '#ec407a',
    'open-peeps-4': '#ffca28',
    'open-peeps-5': '#7e57c2',
    'open-peeps-6': '#29b6f6',
    'open-peeps-7': '#ef5350',
    'open-peeps-8': '#66bb6a',
    'notionists-1': '#ffb300',
    'notionists-2': '#00897b',
    'notionists-3': '#f4511e',
    'notionists-4': '#5e35b1',
    'thumbs-1': '#1a237e',
    'thumbs-2': '#00695c',
    'thumbs-3': '#c2185b',
    'thumbs-4': '#ffd54f',
  };

  /// What the picker offers. The `thumbs-` set was dropped from it, but stays
  /// bundled so profiles that picked one still render.
  static final List<String> images = [
    for (final id in imageColors.keys)
      if (!id.startsWith('thumbs-')) id,
  ];

  static String? imageFor(String? id) =>
      imageColors.containsKey(id) ? 'assets/avatars/$id.png' : null;

  /// Kept so profiles made before the illustrations still render.
  static const Map<String, IconData> presets = {
    'smile': Icons.sentiment_satisfied_alt_rounded,
    'star': Icons.star_rounded,
    'rocket': Icons.rocket_launch_rounded,
    'pets': Icons.pets_rounded,
    'game': Icons.sports_esports_rounded,
    'music': Icons.headphones_rounded,
    'moon': Icons.nightlight_round,
    'bolt': Icons.bolt_rounded,
    'heart': Icons.favorite_rounded,
    'leaf': Icons.eco_rounded,
    'ball': Icons.sports_soccer_rounded,
    'palette': Icons.palette_rounded,
    'cake': Icons.cake_rounded,
    'crown': Icons.workspace_premium_rounded,
    'movie': Icons.movie_rounded,
    'book': Icons.auto_stories_rounded,
  };

  static const List<String> colors = [
    '#e50914',
    '#f5a623',
    '#2ecc71',
    '#1e88e5',
    '#8e44ad',
    '#e91e63',
    '#00acc1',
    '#ff7043',
  ];

  static Color parse(String? hex, String seed) {
    final h = hex?.replaceFirst('#', '');
    if (h != null && h.length == 6) {
      final v = int.tryParse(h, radix: 16);
      if (v != null) return Color(0xFF000000 | v);
    }
    final i = seed.codeUnits.fold<int>(0, (a, b) => a + b) % colors.length;
    return parse(colors[i], '');
  }
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.name,
    this.avatar,
    this.color,
    this.size = 96,
    this.isKids = false,
    this.locked = false,
    this.selected = false,
  });

  ProfileAvatar.of(
    HouseholdProfile profile, {
    Key? key,
    double size = 96,
    bool showLock = true,
    bool selected = false,
  }) : this(
         key: key,
         name: profile.name,
         avatar: profile.avatar,
         color: profile.color,
         size: size,
         isKids: profile.isKids,
         locked: showLock && profile.hasPin,
         selected: selected,
       );

  final String name;
  final String? avatar;
  final String? color;
  final double size;
  final bool isKids;
  final bool locked;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final base = ProfileAvatars.parse(
      ProfileAvatars.imageColors[avatar] ?? color,
      name,
    );
    final icon = ProfileAvatars.presets[avatar];
    final image = ProfileAvatars.imageFor(avatar);
    final initial = name.trim().isEmpty
        ? '?'
        : name.trim().characters.first.toUpperCase();
    final radius = BorderRadius.circular(size * 0.22);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(base, Colors.white, 0.12)!,
                  Color.lerp(base, Colors.black, 0.28)!,
                ],
              ),
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: selected ? Colors.white : Colors.transparent,
                width: size * 0.035,
              ),
            ),
            alignment: Alignment.center,
            clipBehavior: Clip.antiAlias,
            child: image != null
                ? Image.asset(
                    image,
                    width: size,
                    height: size,
                    // Decoded at the size shown: a grid of full 384px bitmaps
                    // made the edit page stutter.
                    cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                  )
                : icon != null
                ? Icon(icon, color: Colors.white, size: size * 0.5)
                : Text(
                    initial,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: size * 0.42,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
          if (isKids && size >= 64)
            PositionedDirectional(
              start: size * 0.08,
              bottom: size * 0.08,
              child: const KidsBadge(),
            ),
          if (locked)
            PositionedDirectional(
              end: size * 0.08,
              top: size * 0.08,
              child: Container(
                padding: EdgeInsets.all(size * 0.045),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_rounded,
                  color: Colors.white,
                  size: (size * 0.16).clamp(10.0, 18.0),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class KidsBadge extends StatelessWidget {
  const KidsBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFFC107),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'profiles.kids_badge'.tr(),
        style: const TextStyle(
          color: Colors.black,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
