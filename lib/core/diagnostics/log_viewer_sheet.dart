import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:soplay/core/system/responsive.dart';

import 'crash_log.dart';
import 'player_log.dart';

class LogViewerSheet extends StatefulWidget {
  const LogViewerSheet({super.key, this.crash = false});

  /// Opens on the crash log instead of the player log.
  final bool crash;

  static Future<void> show(BuildContext context, {bool crash = false}) {
    return showAdaptiveModal<void>(
      context: context,
      backgroundColor: const Color(0xFF0E0E0E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => LogViewerSheet(crash: crash),
    );
  }

  @override
  State<LogViewerSheet> createState() => _LogViewerSheetState();
}

class _LogViewerSheetState extends State<LogViewerSheet> {
  final _scroll = ScrollController();
  final _log = PlayerLog.instance;

  /// Showing the crash log rather than the player log. Only offered where a
  /// crash log exists (off Android).
  bool _crash = false;
  String _crashText = '';

  void _toggleCrash() {
    setState(() {
      _crash = !_crash;
      if (_crash) _crashText = CrashLog.instance?.read() ?? '';
    });
  }

  String get _shareText => _crash ? _crashText : _log.formatForShare();

  void _clear() {
    if (_crash) {
      CrashLog.instance?.clear();
      setState(() => _crashText = '');
    } else {
      _log.clear();
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.crash && CrashLog.instance != null) {
      _crash = true;
      _crashText = CrashLog.instance!.read();
    }
    _log.revision.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
  }

  @override
  void dispose() {
    _log.revision.removeListener(_onChange);
    _scroll.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
  }

  void _jumpToEnd() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _shareText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('player.logs_copied'.tr()),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _share() async {
    await Share.share(
      _shareText,
      subject: _crash ? 'Sozo crash log' : 'Sozo player logs',
    );
  }

  Color _colorFor(LogLevel level) => switch (level) {
    LogLevel.error => const Color(0xFFFF6B6B),
    LogLevel.warn => const Color(0xFFFFC857),
    LogLevel.info => Colors.white70,
  };

  @override
  Widget build(BuildContext context) {
    final lines = _log.lines;
    final hasCrashLog = CrashLog.instance != null;
    final empty = _crash ? _crashText.isEmpty : lines.isEmpty;
    final height = MediaQuery.of(context).size.height;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height * 0.82),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 8, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.bug_report_outlined,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _crash
                        ? 'player.crash_log'.tr()
                        : 'Player logs (${lines.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  if (hasCrashLog)
                    IconButton(
                      tooltip: 'player.crash_log'.tr(),
                      isSelected: _crash,
                      icon: const Icon(
                        Icons.report_gmailerrorred_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                      selectedIcon: const Icon(
                        Icons.report_rounded,
                        color: Color(0xFFFF6B6B),
                        size: 20,
                      ),
                      onPressed: _toggleCrash,
                    ),
                  IconButton(
                    tooltip: 'general.copy'.tr(),
                    icon: const Icon(
                      Icons.copy_rounded,
                      color: Colors.white70,
                      size: 20,
                    ),
                    onPressed: empty ? null : _copy,
                  ),
                  IconButton(
                    tooltip: 'general.share'.tr(),
                    icon: const Icon(
                      Icons.ios_share_rounded,
                      color: Colors.white70,
                      size: 20,
                    ),
                    onPressed: empty ? null : _share,
                  ),
                  IconButton(
                    tooltip: 'general.clear'.tr(),
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.white70,
                      size: 20,
                    ),
                    onPressed: empty ? null : _clear,
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            Flexible(
              child: empty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Text(
                        _crash
                            ? 'player.crash_log_empty'.tr()
                            : 'player.logs_empty'.tr(),
                        style: const TextStyle(color: Colors.white38),
                      ),
                    )
                  : _crash
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                      child: SelectableText(
                        _crashText,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          height: 1.35,
                          color: Colors.white70,
                        ),
                      ),
                    )
                  : Scrollbar(
                      controller: _scroll,
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                        itemCount: lines.length,
                        itemBuilder: (_, i) {
                          final l = lines[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11.5,
                                  height: 1.35,
                                ),
                                children: [
                                  TextSpan(
                                    text: '${_log.stamp(l.time)}  ',
                                    style: const TextStyle(
                                      color: Colors.white30,
                                    ),
                                  ),
                                  TextSpan(
                                    text: l.message,
                                    style: TextStyle(color: _colorFor(l.level)),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
