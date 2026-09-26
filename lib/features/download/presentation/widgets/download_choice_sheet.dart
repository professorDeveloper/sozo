import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/player/hls_variants.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/download_choices.dart';
import 'package:soplay/features/detail/domain/entities/video_source_entity.dart';
import 'package:soplay/features/detail/domain/video_option_groups.dart';
import 'package:soplay/features/download/domain/entities/download_selection.dart';

export 'package:soplay/features/download/domain/entities/download_selection.dart';

Future<DownloadSelection?> chooseDownload(
  BuildContext context, {
  required String url,
  required Map<String, String> headers,
  String? type,
  int? height,
  List<VideoSourceEntity> sources = const [],
}) => showModalBottomSheet<DownloadSelection>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => DownloadChoiceSheet(
    url: url,
    headers: headers,
    type: type,
    height: height,
    sources: sources,
  ),
);

class DownloadChoiceSheet extends StatefulWidget {
  const DownloadChoiceSheet({
    super.key,
    required this.url,
    required this.headers,
    this.type,
    this.height,
    this.sources = const [],
    this.manifestClient,
  });
  final String url;
  final Map<String, String> headers;
  final String? type;
  final int? height;
  final List<VideoSourceEntity> sources;

  /// Optional transport for deterministic manifest tests; owned by this sheet.
  final Dio? manifestClient;

  @override
  State<DownloadChoiceSheet> createState() => _DownloadChoiceSheetState();
}

class _DownloadChoiceSheetState extends State<DownloadChoiceSheet> {
  late final _dio =
      widget.manifestClient ??
      Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
  late final List<VideoSourceEntity> _sources;
  int _source = 0;
  int _variant = 0;
  List<HlsVariant> _variants = [];
  bool _loading = false;
  bool _failed = false;
  CancelToken? _cancel;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    final matching = widget.sources
        .where((s) => s.videoUrl == widget.url)
        .firstOrNull;
    _sources = [
      VideoSourceEntity(
        quality: matching?.quality ?? '',
        videoUrl: widget.url,
        isDefault: true,
        accessible: true,
        headers: widget.headers,
        type: widget.type ?? matching?.type,
        height:
            widget.height ??
            matching?.height ??
            VideoOptionGroups.resolutionOf(matching?.quality ?? ''),
        sizeBytes: matching?.sizeBytes,
      ),
    ];
    final seen = {widget.url};
    for (final s in widget.sources) {
      if (s.accessible &&
          s.drm == null &&
          (s.type == 'hls' ||
              s.type == 'mp4' ||
              s.type == 'video' ||
              RegExp(r'\.(m3u8|mp4|mkv)(\?|$)').hasMatch(s.videoUrl)) &&
          seen.add(s.videoUrl)) {
        _sources.add(s);
      }
    }
    _probe();
  }

  Future<void> _probe() async {
    _cancel?.cancel();
    final revision = ++_revision;
    final source = _sources[_source];
    final isHls =
        source.type == 'hls' ||
        source.type == 'm3u8' ||
        Uri.tryParse(source.videoUrl)?.path.endsWith('.m3u8') == true;
    setState(() {
      _variants = [];
      _variant = 0;
      _failed = false;
      _loading = isHls;
    });
    if (!isHls) return;
    final cancel = _cancel = CancelToken();
    try {
      final result = await _dio.get<String>(
        source.videoUrl,
        options: Options(
          headers: source.headers,
          responseType: ResponseType.plain,
        ),
        cancelToken: cancel,
      );
      if (!mounted || revision != _revision) return;
      setState(() {
        // One row per height. A master routinely carries the same resolution
        // two or three times at different bitrates, and listing those raw gave
        // "1080p, 1080p, 720p, 720p" — rows identical on screen that are not
        // the same file, with no way to tell which one you were choosing.
        _variants = bestPerHeight(
          parseHlsVariants(result.data ?? '', result.realUri),
        );
        _loading = false;
      });
    } catch (_) {
      if (!mounted || revision != _revision) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  /// What to say when there are no renditions to choose between.
  ///
  /// "Quality unknown" over a single Download button reads as the app having
  /// failed to work something out. For an HLS MEDIA playlist — segments rather
  /// than #EXT-X-STREAM-INF — there was nothing to work out: that playlist IS
  /// one quality. But only when this is also the only source; with other
  /// mirrors on offer, "only one quality available" would be a claim about the
  /// title that the list above it contradicts, and unknown is then the honest
  /// word.
  String _noVariantLabel(VideoSourceEntity source) {
    final h = source.height ?? VideoOptionGroups.resolutionOf(source.quality);
    if (h != null && h > 0) return '${h}p';
    if (source.quality.isNotEmpty) return source.quality;
    return _sources.length == 1
        ? 'ux.single_quality'.tr()
        : 'ux.quality_unknown'.tr();
  }

  /// `1080p` when the height is known, the provider's label when it is not.
  String _sourceTitle(VideoSourceEntity source, int index) {
    final h = source.height ?? VideoOptionGroups.resolutionOf(source.quality);
    if (h != null && h > 0) return '${h}p';
    if (source.quality.isNotEmpty) return source.quality;
    return 'ux.source_number'.tr(args: ['${index + 1}']);
  }

  /// What the source called it, kept under the resolution rather than instead
  /// of it — it still names the server, the dub and the container, which is
  /// how somebody tells two 1080p mirrors apart.
  Widget? _sourceSubtitle(VideoSourceEntity source) {
    final h = source.height ?? VideoOptionGroups.resolutionOf(source.quality);
    final size = DownloadChoices.formatSize(source.sizeBytes);
    // Not when the label IS the resolution. Plenty of sources call their
    // renditions exactly "720p", and repeating it under a title that already
    // says 720p is noise in the one place the viewer is reading carefully.
    final label = source.quality.trim();
    final saysHeight = h != null && h > 0 && label.toLowerCase() == '${h}p';
    final parts = <String>[
      if (h != null && h > 0 && label.isNotEmpty && !saysHeight) label,
      if (size != null && size.isNotEmpty) size,
    ];
    if (parts.isEmpty) return null;
    return Text(
      parts.join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
    );
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _dio.close(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final source = _sources[_source];
    final size = DownloadChoices.formatSize(source.sizeBytes);
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  Text(
                    'ux.download_options'.tr(),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ux.download_options_note'.tr(),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  if (_sources.length > 1) ...[
                    const SizedBox(height: 12),
                    for (var i = 0; i < _sources.length; i++)
                      ListTile(
                        // The resolution first, when it can be known, and the
                        // provider's own words under it. `quality` is whatever
                        // the source chose to call this — "SUB HLS", "FHD",
                        // "Server 2" — so a list of them tells you which
                        // button you are pressing and nothing about what you
                        // are about to download.
                        title: Text(_sourceTitle(_sources[i], i)),
                        subtitle: _sourceSubtitle(_sources[i]),
                        trailing: i == _source ? const Icon(Icons.check) : null,
                        selected: i == _source,
                        onTap: () {
                          _source = i;
                          _probe();
                        },
                      ),
                  ],
                  const SizedBox(height: 12),
                  if (_loading) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    Text('ux.checking_quality'.tr()),
                  ] else if (_failed) ...[
                    Text('ux.quality_unavailable'.tr()),
                    TextButton(
                      onPressed: _probe,
                      child: Text('general.retry'.tr()),
                    ),
                  ] else if (_variants.isNotEmpty)
                    for (var i = 0; i < _variants.length; i++)
                      ListTile(
                        title: Text(describeVariant(_variants[i])),
                        selected: i == _variant,
                        trailing: i == _variant
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () => setState(() => _variant = i),
                      )
                  else
                    // One rendition, not an unknown one.
                    //
                    // A playlist with segments rather than #EXT-X-STREAM-INF
                    // offers exactly one quality — that is what it IS, and the
                    // sheet said "Quality unknown" over a single Download
                    // button, which reads as the app having failed to work
                    // something out. It had nothing to work out. The height is
                    // still shown whenever it can be derived at all.
                    Text(_noVariantLabel(source)),
                  const SizedBox(height: 12),
                  // A master size cannot describe a selected rendition; never reuse it.
                  Text(
                    size != null && _variants.isEmpty
                        ? size
                        : 'ux.size_unknown'.tr(),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: _loading
                    ? null
                    : () async {
                        final variant = _variants.isEmpty
                            ? null
                            : _variants[_variant];
                        // A file the host signs per device (asilmedia):
                        // fetched unsigned it is a 403, so sign it first,
                        // with the headers the download will send.
                        var url = variant?.url ?? source.videoUrl;
                        final signer = source.signer;
                        if (variant == null && signer != null) {
                          setState(() => _loading = true);
                          url = await signer.sign(url, source.headers) ?? url;
                          if (!context.mounted) return;
                        }
                        Navigator.pop(
                          context,
                          DownloadSelection(
                            url: url,
                            headers: source.headers,
                            // The label is a last resort, but it is a real
                            // one: plenty of sources declare no height and
                            // call the rendition "1080p" in words. Without
                            // this the downloads list said "quality unknown"
                            // about a file whose quality was written on the
                            // row the viewer had just tapped.
                            height: _failed
                                ? null
                                : variant?.height ??
                                      source.height ??
                                      VideoOptionGroups.resolutionOf(
                                        source.quality,
                                      ),
                          ),
                        );
                      },
                child: Text('detail.download_action'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
