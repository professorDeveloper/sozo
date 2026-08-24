import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/features/extensions/data/mangayomi_repo_store.dart';
import 'package:soplay/core/manga/manga_channel.dart';
import 'package:soplay/core/theme/app_colors.dart';

/// Handles "Open with Sozo" on an extension repository index file.
///
/// Extension repos ship as a single index — `index.pb` (Mihon/Keiyoushi,
/// gzipped protobuf), `index.min.json` (Aniyomi), `repo.json` (CloudStream).
/// Tapping one in a browser, file manager or chat app now offers Sozo; the
/// native side (`RepoFileIntent`) resolves the intent and parks the result, and
/// this pulls it and shows the install sheet.
///
/// Kept as a plain service + one sheet rather than a route so it can fire over
/// whatever screen the user happens to be on, including a cold start.
class RepoFileImport {
  RepoFileImport._();

  static const MethodChannel _ch = MethodChannel('soplay/repo_file');

  /// Android and iOS both implement the `soplay/repo_file` channel — on iOS via
  /// `RepoFileImport.swift` and the scene delegate's URL contexts. Desktop has
  /// no document-open plumbing, so it opts out.
  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  static bool _listening = false;
  static BuildContext? Function()? _contextProvider;

  /// Starts listening for files opened while the app is already running, and
  /// drains anything parked from a cold start.
  ///
  /// [contextProvider] returns the current navigator context — the app root
  /// outlives any single screen, so a captured context would go stale.
  static void start(BuildContext? Function() contextProvider) {
    if (!isSupported) return;
    _contextProvider = contextProvider;
    if (!_listening) {
      _listening = true;
      _ch.setMethodCallHandler((call) async {
        if (call.method == 'openRepoFile') {
          _present(call.arguments as String?);
        }
        return null;
      });
    }
    // Cold start: the intent arrived before Dart was listening.
    unawaited(drainPending());
  }

  /// Pulls and presents anything the native side parked. Safe to call repeatedly
  /// — the native side hands each payload out exactly once.
  static Future<void> drainPending() async {
    if (!isSupported) return;
    try {
      final payload = await _ch.invokeMethod<String>('takePending');
      _present(payload);
    } on MissingPluginException {
      // Older host without the channel — nothing to drain.
    } on PlatformException {
      // Nothing parked.
    }
  }

  static void _present(String? payload) {
    if (payload == null || payload.isEmpty) return;
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return;
      data = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }
    final context = _contextProvider?.call();
    if (context == null || !context.mounted) return;
    // Let the current frame settle — on a cold start this fires while the first
    // route is still being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _contextProvider?.call();
      if (ctx == null || !ctx.mounted) return;
      showModalBottomSheet<void>(
        context: ctx,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => _RepoFileSheet(data: data),
      );
    });
  }
}

/// Which host installs the opened file.
///
/// An ambiguous file is the norm, not an edge case: `index.pb` and
/// `index.min.json` are shared by the manga and anime ecosystems and the file
/// itself does not say which, so the user picks.
///
/// [mangayomi] is the only target available on iOS — the other two install
/// Android APKs. That is also why it is offered everywhere rather than being
/// hidden behind a platform check.
enum _Target { manga, aniyomi, mangayomi }

class _RepoFileSheet extends StatefulWidget {
  const _RepoFileSheet({required this.data});

  final Map<String, dynamic> data;

  @override
  State<_RepoFileSheet> createState() => _RepoFileSheetState();
}

class _RepoFileSheetState extends State<_RepoFileSheet> {
  late _Target _target = _initialTarget();

  /// Android APK hosts only exist on Android; everywhere else Mangayomi's
  /// JavaScript extensions are the only thing that can be installed.
  static bool get _apkHostsAvailable => Platform.isAndroid;

  _Target _initialTarget() {
    if (!_apkHostsAvailable) return _Target.mangayomi;
    return switch (widget.data['kind'] as String?) {
      'aniyomi' => _Target.aniyomi,
      'mangayomi' => _Target.mangayomi,
      _ => _Target.manga,
    };
  }
  bool _busy = false;
  String? _result;
  bool _error = false;

  String get _name =>
      (widget.data['name'] as String?)?.trim().isNotEmpty == true
          ? widget.data['name'] as String
          : 'index';

  String? get _path => (widget.data['path'] as String?)?.trim();
  String? get _url => (widget.data['url'] as String?)?.trim();

  /// True when the native side could not pin the ecosystem down — the two
  /// index formats are shared, so this is the normal case, not an error.
  bool get _ambiguous {
    final k = widget.data['kind'] as String?;
    return k == null || k == 'unknown';
  }

  Future<void> _install() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = false;
      _result = 'Installing…';
    });
    try {
      var count = 0;
      if (_target == _Target.mangayomi) {
        // Mangayomi indexes are plain JSON fetched in Dart, so this branch is
        // the one that works on iOS. A local file has no url to re-fetch, so
        // only the url form is supported here.
        final url = _url;
        if (url == null || url.isEmpty) {
          throw Exception(
              'Mangayomi repos install from a URL — open the index link '
              'instead of a downloaded copy.');
        }
        final res = await getIt<MangayomiRepoStore>().addRepo(url);
        count = res['added'] ?? 0;
      } else {
        final Map<String, dynamic> res;
        if (_url != null && _url!.isNotEmpty) {
          res = _target == _Target.aniyomi
              ? await AniyomiChannel.addRepo(_url!)
              : await MangaChannel.addRepo(_url!);
        } else if (_path != null && _path!.isNotEmpty) {
          res = _target == _Target.aniyomi
              ? await AniyomiChannel.addRepoFile(_path!, name: _name)
              : await MangaChannel.addRepoFile(_path!, name: _name);
        } else {
          res = const {};
        }
        count = (res['sourceCount'] as num?)?.toInt() ?? 0;
      }
      if (!mounted) return;
      setState(() {
        _error = count == 0;
        _result = count == 0
            ? 'No extensions found in this file. It may be for a different app, '
                'or the wrong type was selected.'
            : 'Installed $count source(s).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _result = 'Error: $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = _result != null && !_busy && !_error;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textHint.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(Icons.extension_rounded,
                      color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Install extension repo?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textHint, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_ambiguous && _apkHostsAvailable)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Anime and manga repos use the same file format, so pick which '
                  'library this one belongs to.',
                  style: TextStyle(
                      color: AppColors.textHint, fontSize: 12, height: 1.35),
                ),
              ),
            if (!_apkHostsAvailable)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'On this platform only Mangayomi (JavaScript) extensions can '
                  'be installed — CloudStream, Aniyomi and Mihon repos ship '
                  'Android app packages.',
                  style: TextStyle(
                      color: AppColors.textHint, fontSize: 12, height: 1.35),
                ),
              ),
            SegmentedButton<_Target>(
              segments: [
                if (_apkHostsAvailable) ...const [
                  ButtonSegment(
                    value: _Target.manga,
                    label: Text('Manga'),
                    icon: Icon(Icons.menu_book_outlined, size: 16),
                  ),
                  ButtonSegment(
                    value: _Target.aniyomi,
                    label: Text('Anime'),
                    icon: Icon(Icons.play_circle_outline, size: 16),
                  ),
                ],
                const ButtonSegment(
                  value: _Target.mangayomi,
                  label: Text('Mangayomi'),
                  icon: Icon(Icons.javascript_outlined, size: 16),
                ),
              ],
              selected: {_target},
              onSelectionChanged:
                  _busy ? null : (s) => setState(() => _target = s.first),
            ),
            if (_result != null) ...[
              const SizedBox(height: 14),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: (_error ? Colors.redAccent : Colors.green)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _result!,
                  style: TextStyle(
                    color: _error ? Colors.redAccent : Colors.green,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed: _busy
                    ? null
                    : done
                        ? () => Navigator.of(context).pop()
                        : _install,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(done ? Icons.check : Icons.download_rounded),
                label: Text(
                  _busy
                      ? 'Installing…'
                      : done
                          ? 'Done'
                          : 'Install',
                ),
              ),
            ),
            if (!done)
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel',
                    style: TextStyle(color: AppColors.textHint)),
              ),
          ],
        ),
      ),
    );
  }
}
