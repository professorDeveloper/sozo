import 'package:soplay/core/network/image_headers.dart';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_colors.dart';
// Re-exported so the dozen existing `ShimmerWrapper` call sites in this
// feature keep working while the definition lives in core.
export 'package:soplay/core/widgets/shimmer_wrapper.dart';

class HomeNetworkImage extends StatelessWidget {
  const HomeNetworkImage({
    super.key,
    required this.url,
    required this.borderRadius,
    required this.placeholderIcon,
    this.fit = BoxFit.cover,
    this.headers,
    this.memCacheWidth,
  });

  final String? url;
  final BorderRadius borderRadius;
  final IconData placeholderIcon;
  final BoxFit fit;

  final Map<String, String>? headers;

  /// Overrides the width this decodes at, instead of measuring it.
  ///
  /// Exists so a caller can hand the SAME value to a [PosterHero] wrapped
  /// around this widget. `memCacheWidth` becomes a `ResizeImage` wrapper and
  /// therefore part of the image-cache key, so a shuttle that computes its own
  /// width misses the cache the grid already filled — and flies a blank frame.
  final int? memCacheWidth;

  /// Moved to core/network/image_headers.dart so the hero shuttle and the
  /// detail header send byte-identical headers to the same host.
  static Map<String, String>? _defaultHeaders(String url) =>
      posterImageHeaders(url);

  @override
  Widget build(BuildContext context) {
    final imageUrl = url;
    if (imageUrl == null || imageUrl.isEmpty) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: HomeImagePlaceholder(icon: placeholderIcon),
      );
    }

    if (_isLocalPath(imageUrl)) {
      final file = imageUrl.startsWith('file://')
          ? File(Uri.parse(imageUrl).toFilePath())
          : File(imageUrl);
      return ClipRRect(
        borderRadius: borderRadius,
        child: Image.file(
          file,
          fit: fit,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, _, _) =>
              HomeImagePlaceholder(icon: placeholderIcon),
        ),
      );
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final w =
              memCacheWidth ??
              ((!isDesktopPlatform && constraints.maxWidth.isFinite)
                  ? (constraints.maxWidth * dpr).round()
                  : null);
          // CachedNetworkImage, not Image.network.
          //
          // `Image.network` caches in memory only. Flutter's image cache is
          // bounded and cleared with the process, so every cold start — and
          // every return after the OS trimmed the app — re-downloaded all
          // forty-odd posters on the home screen. On a slow connection that is
          // a screen of grey placeholders filling in one by one, which is what
          // "the app is slow" looks like when the app itself is doing nothing
          // wrong.
          //
          // The disk cache makes the second launch instant. The package was
          // already a dependency and already used in thirty other places; home,
          // the most image-heavy screen in the app, was the one that was not.
          return CachedNetworkImage(
            imageUrl: imageUrl,
            httpHeaders: headers ?? _defaultHeaders(imageUrl),
            fit: fit,
            width: double.infinity,
            height: double.infinity,
            // Decoded at the size it is drawn at, not at the size it was
            // published at. A 500px poster in a 110px tile costs twenty times
            // the memory it needs, and the cost is paid per tile.
            memCacheWidth: (w != null && w > 0) ? w : null,
            filterQuality:
                isDesktopPlatform ? FilterQuality.medium : FilterQuality.low,
            // Same widget for both, so a tile that is loading and a tile that
            // failed do not jump between two different shapes.
            errorWidget: (_, _, _) =>
                HomeImagePlaceholder(icon: placeholderIcon),
            placeholder: (_, _) => HomeImagePlaceholder(icon: placeholderIcon),
            // No cross-fade: these arrive in a scrolling rail, and forty tiles
            // fading in at slightly different times is more distracting than
            // forty tiles appearing.
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
          );
        },
      ),
    );
  }

  /// A Windows drive letter, compiled once.
  ///
  /// This is checked from [build], once per poster. Compiling the pattern there
  /// allocated a fresh RegExp for every tile on every rebuild — forty-odd of
  /// them per home scroll frame — to answer a question whose answer is fixed.
  static final RegExp _windowsPath = RegExp(r'^[A-Za-z]:[\\/]');

  bool _isLocalPath(String value) {
    if (value.startsWith('file://')) return true;
    return value.startsWith('/') || _windowsPath.hasMatch(value);
  }
}

class HomeImagePlaceholder extends StatelessWidget {
  const HomeImagePlaceholder({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceVariant,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Icon(icon, color: AppColors.textHint, size: 28),
        ),
      ),
    );
  }
}

/// Reserves the vertical space of [lines] text lines whether or not [child]
/// has anything to draw.
///
/// Poster rails size their cover with an [Expanded], so a card whose caption
/// happens to be one line shorter than its neighbour's silently gets a TALLER
/// poster — the row ends up ragged. Reserving the caption box keeps every
/// poster in a rail identical, and scales with the user's text size.
class FixedTextLines extends StatelessWidget {
  const FixedTextLines({
    super.key,
    required this.fontSize,
    required this.lineHeight,
    this.lines = 1,
    this.child,
  });

  final double fontSize;
  final double lineHeight;
  final int lines;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scaled = MediaQuery.textScalerOf(context).scale(fontSize);
    return SizedBox(height: scaled * lineHeight * lines, child: child);
  }
}

class HomeSkeletonBox extends StatelessWidget {
  const HomeSkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = 8,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(width: width, height: height, color: Colors.white),
    );
  }
}

/// Press feedback for a section header strip on Home.
///
/// Every rail's header is the tap target for its "View all" — a deliberate
/// earlier fix, since the old `TextButton` was a ~26dp target squeezed into the
/// row. But the strip was a bare [InkWell], and a bare InkWell across a
/// full-width header is the wrong feedback twice over: the splash is an
/// edge-to-edge rectangle with no radius, which reads as a rendering artifact
/// rather than as a button, and Material's default splash on a near-black
/// surface is so faint that on most taps nothing visible happens at all.
///
/// So the ink is switched off and the row answers instead — it dips and settles
/// back, the same press language the cards below it already use. The InkWell
/// itself stays, because it is what carries focus, hover and semantics; only
/// its painting is replaced.
class HomeSectionTapTarget extends StatefulWidget {
  const HomeSectionTapTarget({super.key, required this.child, this.onTap});

  final Widget child;

  /// Null disables the press effect along with the tap, so a header with
  /// nothing to open does not pretend otherwise.
  final VoidCallback? onTap;

  @override
  State<HomeSectionTapTarget> createState() => _HomeSectionTapTargetState();
}

class _HomeSectionTapTargetState extends State<HomeSectionTapTarget> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;

    return InkWell(
      onTap: widget.onTap,
      // Transparent, not absent: keeping the InkWell keeps focus traversal —
      // which the TV build depends on — and the semantics that make the strip
      // announce as a button.
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.white.withValues(alpha: 0.025),
      onHighlightChanged: enabled
          ? (value) {
              if (value != _pressed) setState(() => _pressed = value);
            }
          : null,
      child: AnimatedScale(
        // Barely there on purpose: a header is a large surface, and a scale big
        // enough to notice on a button looks like the layout jumped here.
        scale: _pressed && enabled ? 0.985 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _pressed && enabled ? 0.6 : 1,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}
