import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/support/data/support_models.dart';
import 'package:soplay/features/support/data/support_repository.dart';

/// Lets the viewer choose up to [remaining] screenshots.
///
/// Scaled down on the way in (a screenshot needs no more than 1920 px on its
/// long side to be read), which keeps them far under the 5 MB limit; anything
/// still over it, or of a type the server does not take, is left out and
/// said so.
Future<List<File>> pickSupportScreenshots(
  BuildContext context,
  int remaining,
) async {
  if (remaining <= 0) return const [];
  final picker = ImagePicker();
  List<XFile> picked;
  try {
    picked = remaining == 1
        ? [
            ?await picker.pickImage(
              source: ImageSource.gallery,
              maxWidth: 1920,
              maxHeight: 1920,
              imageQuality: 85,
            ),
          ]
        : await picker.pickMultiImage(
            limit: remaining,
            maxWidth: 1920,
            maxHeight: 1920,
            imageQuality: 85,
          );
  } on PlatformException {
    return const [];
  }
  final out = <File>[];
  var skipped = 0;
  for (final x in picked.take(remaining)) {
    final file = File(x.path);
    final ok =
        SupportRepository.contentTypeFor(x.path) != null &&
        await file.length() <= SupportRepository.maxAttachmentBytes;
    ok ? out.add(file) : skipped++;
  }
  if (skipped > 0 && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('support.screenshots_skipped'.tr())));
  }
  return out;
}

/// The screenshots chosen for a message that is not sent yet.
class ScreenshotStrip extends StatelessWidget {
  const ScreenshotStrip({
    super.key,
    required this.files,
    required this.onRemove,
    this.onAdd,
    this.height = 112,
  });

  final List<File> files;
  final ValueChanged<int> onRemove;

  /// Null when no more can be added (or while sending).
  final VoidCallback? onAdd;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < files.length; i++)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      files[i],
                      width: height * 0.62,
                      height: height,
                      fit: BoxFit.cover,
                      cacheWidth: 240,
                    ),
                  ),
                  PositionedDirectional(
                    top: 4,
                    end: 4,
                    child: GestureDetector(
                      onTap: () => onRemove(i),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 15,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (onAdd != null)
            InkWell(
              onTap: onAdd,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: height * 0.62,
                height: height,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.add_photo_alternate_outlined,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${files.length}/${SupportRepository.maxAttachments}',
                      style: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 11,
                      ),
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

/// Screenshots on a sent message; a tap opens them full screen.
class AttachmentGrid extends StatelessWidget {
  const AttachmentGrid({super.key, required this.items});

  final List<SupportAttachment> items;

  @override
  Widget build(BuildContext context) {
    final single = items.length == 1;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < items.length; i++)
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SupportImageViewer(items: items, initial: i),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                items[i].url,
                width: single ? 170 : 96,
                height: single ? 280 : 156,
                fit: BoxFit.cover,
                cacheWidth: single ? 510 : 288,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : Container(
                        width: single ? 170 : 96,
                        height: single ? 280 : 156,
                        color: Colors.white.withValues(alpha: 0.05),
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                errorBuilder: (context, _, _) => Container(
                  width: single ? 170 : 96,
                  height: single ? 280 : 156,
                  color: Colors.white.withValues(alpha: 0.05),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.broken_image_outlined,
                    color: AppColors.textHint,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class SupportImageViewer extends StatefulWidget {
  const SupportImageViewer({
    super.key,
    required this.items,
    required this.initial,
  });

  final List<SupportAttachment> items;
  final int initial;

  @override
  State<SupportImageViewer> createState() => _SupportImageViewerState();
}

class _SupportImageViewerState extends State<SupportImageViewer> {
  late final PageController _pages = PageController(
    initialPage: widget.initial,
  );
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          '${_index + 1} / ${widget.items.length}',
          style: const TextStyle(fontSize: 15),
        ),
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: widget.items.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: Image.network(widget.items[i].url, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
