import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/player/hls_variants.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/download_choices.dart';
import 'package:soplay/features/detail/domain/entities/video_source_entity.dart';
import 'package:soplay/features/detail/domain/video_option_groups.dart';

/// A concrete file/rendition, not the quality currently used by the player.
class DownloadSelection {
  const DownloadSelection({
    required this.url,
    required this.headers,
    this.height,
  });
  final String url;
  final Map<String, String> headers;
  final int? height;
}

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
        _variants = parseHlsVariants(result.data ?? '', result.realUri);
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
                        title: Text(
                          _sources[i].quality.isEmpty
                              ? 'ux.source_number'.tr(args: ['${i + 1}'])
                              : _sources[i].quality,
                        ),
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
                        title: Text('${_variants[i].height}p'),
                        selected: i == _variant,
                        trailing: i == _variant
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () => setState(() => _variant = i),
                      )
                  else
                    Text(
                      source.height == null
                          ? 'ux.quality_unknown'.tr()
                          : '${source.height}p',
                    ),
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
                    : () {
                        final variant = _variants.isEmpty
                            ? null
                            : _variants[_variant];
                        Navigator.pop(
                          context,
                          DownloadSelection(
                            url: variant?.url ?? source.videoUrl,
                            headers: source.headers,
                            height: _failed
                                ? null
                                : variant?.height ?? source.height,
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
