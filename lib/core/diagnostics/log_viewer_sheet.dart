import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:soplay/core/system/responsive.dart';

import 'player_log.dart';

class LogViewerSheet extends StatefulWidget {
  const LogViewerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showAdaptiveModal<void>(
      context: context,
      backgroundColor: const Color(0xFF0E0E0E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const LogViewerSheet(),
    );
  }

  @override
  State<LogViewerSheet> createState() => _LogViewerSheetState();
}

class _LogViewerSheetState extends State<LogViewerSheet> {
  final _scroll = ScrollController();
  final _log = PlayerLog.instance;

  @override
  void initState() {
    super.initState();
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
    await Clipboard.setData(ClipboardData(text: _log.formatForShare()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logs copied'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _share() async {
    await Share.share(_log.formatForShare(), subject: 'Soplay player logs');
  }

  Color _colorFor(LogLevel level) => switch (level) {
        LogLevel.error => const Color(0xFFFF6B6B),
        LogLevel.warn => const Color(0xFFFFC857),
        LogLevel.info => Colors.white70,
      };

  @override
  Widget build(BuildContext context) {
    final lines = _log.lines;
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
                  const Icon(Icons.bug_report_outlined,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    'Player logs (${lines.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Copy',
                    icon: const Icon(Icons.copy_rounded,
                        color: Colors.white70, size: 20),
                    onPressed: lines.isEmpty ? null : _copy,
                  ),
                  IconButton(
                    tooltip: 'Share',
                    icon: const Icon(Icons.ios_share_rounded,
                        color: Colors.white70, size: 20),
                    onPressed: lines.isEmpty ? null : _share,
                  ),
                  IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: Colors.white70, size: 20),
                    onPressed: lines.isEmpty ? null : _log.clear,
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            Flexible(
              child: lines.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Text('No logs yet',
                          style: TextStyle(color: Colors.white38)),
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
                                        color: Colors.white30),
                                  ),
                                  TextSpan(
                                    text: l.message,
                                    style: TextStyle(
                                        color: _colorFor(l.level)),
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
