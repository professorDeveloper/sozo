import 'package:easy_localization/easy_localization.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/entities/screenshot_entity.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_empty_state.dart';

class DetailScreenshotsSection extends StatelessWidget {
  const DetailScreenshotsSection({super.key, required this.screenshots});
  final List<ScreenshotEntity> screenshots;

  @override
  Widget build(BuildContext context) {
    final valid = screenshots
        .where((s) => s.thumb.isNotEmpty || s.full.isNotEmpty)
        .toList();
    if (valid.isEmpty) {
      return DetailEmptyState(
        icon: Icons.image_outlined,
        message: 'detail.no_screenshots'.tr(),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        gridDelegate: responsiveGridDelegate(
          mobileCrossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 16 / 9,
          desktopMaxCrossAxisExtent: 320,
        ),
        itemCount: valid.length,
        itemBuilder: (context, i) => _ScreenshotCard(
          screenshot: valid[i],
          onTap: () => _showFullscreen(context, valid, i),
        ),
      ),
    );
  }

  void _showFullscreen(
    BuildContext context,
    List<ScreenshotEntity> items,
    int initial,
  ) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 220),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
        pageBuilder: (_, _, _) =>
            _FullscreenGallery(screenshots: items, initialIndex: initial),
      ),
    );
  }
}

class _ScreenshotCard extends StatelessWidget {
  const _ScreenshotCard({required this.screenshot, required this.onTap});
  final ScreenshotEntity screenshot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final url = screenshot.thumb.isNotEmpty ? screenshot.thumb : screenshot.full;
    return HoverTap(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 180),
              placeholder: (_, _) =>
                  ColoredBox(color: AppColors.surfaceVariant),
              errorWidget: (_, _, _) => const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: AppColors.textHint,
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.center,
                  colors: [Color(0x66000000), Color(0x00000000)],
                ),
              ),
            ),
            const Center(
              child: Icon(
                Icons.zoom_in_rounded,
                color: Colors.white70,
                size: 32,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullscreenGallery extends StatefulWidget {
  const _FullscreenGallery({
    required this.screenshots,
    required this.initialIndex,
  });
  final List<ScreenshotEntity> screenshots;
  final int initialIndex;

  @override
  State<_FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<_FullscreenGallery> {
  late final PageController _ctrl;
  late int _index;
  bool _chromeVisible = true;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _ctrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onPageChanged(int i) {
    setState(() => _index = i);
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _ctrl,
            itemCount: widget.screenshots.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (_, i) {
              final url = widget.screenshots[i].full.isNotEmpty
                  ? widget.screenshots[i].full
                  : widget.screenshots[i].thumb;
              return _ZoomablePhoto(
                url: url,
                onChromeToggle: () =>
                    setState(() => _chromeVisible = !_chromeVisible),
              );
            },
          ),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: _chromeVisible ? 1 : 0,
            child: IgnorePointer(
              ignoring: !_chromeVisible,
              child: SafeArea(
                child: Stack(
                  children: [
                    Positioned(
                      top: 8,
                      left: 12,
                      child: _CircleButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onTap: _close,
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 12,
                      child: _CircleButton(
                        icon: Icons.close_rounded,
                        onTap: _close,
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_index + 1} / ${widget.screenshots.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({required this.url, required this.onChromeToggle});
  final String url;
  final VoidCallback onChromeToggle;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto>
    with SingleTickerProviderStateMixin {
  static const double _maxScale = 4;
  static const double _doubleTapScale = 2.5;

  late final TransformationController _transform;
  late final AnimationController _animator;
  Animation<Matrix4>? _animation;
  TapDownDetails? _lastTap;

  @override
  void initState() {
    super.initState();
    _transform = TransformationController();
    _animator = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(_onAnimate);
  }

  void _onAnimate() {
    final anim = _animation;
    if (anim != null) _transform.value = anim.value;
  }

  @override
  void dispose() {
    _animator
      ..removeListener(_onAnimate)
      ..dispose();
    _transform.dispose();
    super.dispose();
  }

  void _animateTo(Matrix4 target) {
    _animation = Matrix4Tween(begin: _transform.value, end: target).animate(
      CurvedAnimation(parent: _animator, curve: Curves.easeOutCubic),
    );
    _animator
      ..stop()
      ..value = 0
      ..forward();
  }

  void _handleDoubleTap() {
    final isZoomed = _transform.value != Matrix4.identity();
    if (isZoomed) {
      _animateTo(Matrix4.identity());
      return;
    }
    final tapPos = _lastTap?.localPosition;
    if (tapPos == null) {
      final centered = Matrix4.identity()..scaleByDouble(
        _doubleTapScale,
        _doubleTapScale,
        1,
        1,
      );
      _animateTo(centered);
      return;
    }
    final target = Matrix4.identity()
      ..translateByDouble(
        -tapPos.dx * (_doubleTapScale - 1),
        -tapPos.dy * (_doubleTapScale - 1),
        0,
        1,
      )
      ..scaleByDouble(_doubleTapScale, _doubleTapScale, 1, 1);
    _animateTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onChromeToggle,
      onDoubleTapDown: (details) => _lastTap = details,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _transform,
        clipBehavior: Clip.none,
        minScale: 1,
        maxScale: _maxScale,
        child: Center(
          child: CachedNetworkImage(
            imageUrl: widget.url,
            fit: BoxFit.contain,
            // The full-screen view opens on a thumbnail the grid already
            // cached, so the large copy is usually a decode away rather than a
            // download — the spinner is for the first open only.
            errorWidget: (_, _, _) => const Icon(
              Icons.broken_image_outlined,
              color: AppColors.textHint,
              size: 48,
            ),
            progressIndicatorBuilder: (_, _, _) {
              return const SizedBox(
                width: 38,
                height: 38,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}
