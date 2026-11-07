import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/manga/domain/translate/page_translation.dart';

/// The translated lettering, laid over a page drawn at any size.
///
/// Sized by its parent, which is the page image: block rectangles are in the
/// image's pixels and are scaled to whatever the page is drawn at.
class PageTranslationOverlay extends StatelessWidget {
  const PageTranslationOverlay({super.key, required this.translation});

  final PageTranslation translation;

  @override
  Widget build(BuildContext context) {
    final rtl = isRtlLanguage(translation.targetLang);
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final image = translation.imageSize;
          if (image.isEmpty || !constraints.maxWidth.isFinite) {
            return const SizedBox.shrink();
          }
          final sx = constraints.maxWidth / image.width;
          final sy = constraints.maxHeight.isFinite
              ? constraints.maxHeight / image.height
              : sx;
          return Stack(
            children: [
              for (final block in translation.blocks)
                _box(block, sx, sy, constraints.biggest, rtl),
            ],
          );
        },
      ),
    );
  }

  Widget _box(TranslatedBlock block, double sx, double sy, Size area, bool rtl) {
    final r = block.rect;
    // A little wider than the letters, so their edges do not peek out.
    final pad = math.max(3.0, 0.15 * math.min(r.width * sx, r.height * sy));
    final left = math.max(0.0, r.left * sx - pad);
    final top = math.max(0.0, r.top * sy - pad);
    final right = area.width.isFinite
        ? math.min(area.width, r.right * sx + pad)
        : r.right * sx + pad;
    final bottom = area.height.isFinite
        ? math.min(area.height, r.bottom * sy + pad)
        : r.bottom * sy + pad;
    return Positioned(
      left: left,
      top: top,
      width: math.max(0.0, right - left),
      height: math.max(0.0, bottom - top),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(
            math.min(12.0, 0.3 * math.min(right - left, bottom - top)),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: FittedLettering(
            text: block.text,
            direction: rtl ? TextDirection.rtl : TextDirection.ltr,
          ),
        ),
      ),
    );
  }
}

/// Text at the largest size that fits its box.
class FittedLettering extends StatelessWidget {
  const FittedLettering({
    super.key,
    required this.text,
    required this.direction,
  });

  final String text;
  final TextDirection direction;

  static TextStyle styleAt(double size) => TextStyle(
    color: Colors.black,
    fontSize: size,
    height: 1.15,
    fontWeight: FontWeight.w600,
  );

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = constraints.biggest;
        final size = fitFontSize(
          box: box,
          max: math.max(6.0, math.min(40.0, box.height)),
          measure: (fontSize) {
            final painter = TextPainter(
              text: TextSpan(text: text, style: styleAt(fontSize)),
              textAlign: TextAlign.center,
              textDirection: direction,
              textScaler: scaler,
            )..layout(maxWidth: box.width);
            final used = Size(
              math.max(painter.width, painter.minIntrinsicWidth),
              painter.height,
            );
            painter.dispose();
            return used;
          },
        );
        return Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            textDirection: direction,
            overflow: TextOverflow.clip,
            style: styleAt(size),
          ),
        );
      },
    );
  }
}

/// What the person chose in the preview. Null from the route means Cancel.
class PageTranslatePreviewResult {
  const PageTranslatePreviewResult({required this.showOriginal});
  final bool showOriginal;
}

/// The page with its translation over it, before anything changes in the
/// reader: Apply, Show original, Cancel.
class PageTranslatePreview extends StatefulWidget {
  const PageTranslatePreview({
    super.key,
    required this.image,
    required this.translation,
    this.showOriginal = false,
  });

  final ImageProvider image;
  final PageTranslation translation;
  final bool showOriginal;

  @override
  State<PageTranslatePreview> createState() => _PageTranslatePreviewState();
}

class _PageTranslatePreviewState extends State<PageTranslatePreview> {
  late bool _original = widget.showOriginal;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primary;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          'manga.translate_preview'.tr(),
          style: const TextStyle(fontSize: 16),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Stack(
                children: [
                  Image(
                    image: widget.image,
                    fit: BoxFit.fitWidth,
                    width: double.infinity,
                  ),
                  if (!_original)
                    Positioned.fill(
                      child: PageTranslationOverlay(
                        translation: widget.translation,
                      ),
                    ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'general.cancel'.tr(),
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  const Spacer(),
                  FilterChip(
                    selected: _original,
                    onSelected: (v) => setState(() => _original = v),
                    label: Text('manga.translate_show_original'.tr()),
                    selectedColor: accent.withValues(alpha: 0.3),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: accent),
                    onPressed: () => Navigator.of(context).pop(
                      PageTranslatePreviewResult(showOriginal: _original),
                    ),
                    child: Text('manga.translate_apply'.tr()),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
