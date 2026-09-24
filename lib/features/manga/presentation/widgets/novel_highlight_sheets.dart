import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/features/manga/domain/reading/novel_highlight.dart';

class HighlightEdit {
  const HighlightEdit({
    required this.color,
    required this.note,
    this.delete = false,
  });

  final HighlightColor color;
  final String note;
  final bool delete;
}

/// Picks a colour and an optional note for a passage. Null when dismissed.
Future<HighlightEdit?> showHighlightEditor(
  BuildContext context, {
  required String quote,
  required Color accent,
  HighlightColor color = HighlightColor.yellow,
  String note = '',
  bool existing = false,
}) {
  return showAdaptiveModal<HighlightEdit>(
    context: context,
    backgroundColor: const Color(0xFF161616),
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _HighlightEditor(
      quote: quote,
      accent: accent,
      color: color,
      note: note,
      existing: existing,
    ),
  );
}

class _HighlightEditor extends StatefulWidget {
  const _HighlightEditor({
    required this.quote,
    required this.accent,
    required this.color,
    required this.note,
    required this.existing,
  });

  final String quote;
  final Color accent;
  final HighlightColor color;
  final String note;
  final bool existing;

  @override
  State<_HighlightEditor> createState() => _HighlightEditorState();
}

class _HighlightEditorState extends State<_HighlightEditor> {
  late HighlightColor _color = widget.color;
  late final TextEditingController _note = TextEditingController(
    text: widget.note,
  );

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(
    context,
  ).pop(HighlightEdit(color: _color, note: _note.text.trim()));

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
              decoration: BoxDecoration(
                color: Color(_color.argb).withValues(alpha: 0.12),
                border: Border(
                  left: BorderSide(color: Color(_color.argb), width: 3),
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                widget.quote,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13.5,
                  height: 1.45,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                for (final c in HighlightColor.values)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 12),
                    child: _swatch(c),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'manga.highlight_note'.tr(),
                prefixIcon: const Icon(Icons.sticky_note_2_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                if (widget.existing)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                    ),
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(HighlightEdit(color: _color, note: '', delete: true)),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: Text('manga.remove_highlight'.tr()),
                  ),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: widget.accent),
                  onPressed: _save,
                  child: Text('general.save'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _swatch(HighlightColor c) {
    final selected = c == _color;
    return Semantics(
      selected: selected,
      button: true,
      label: c.name,
      child: HoverTap(
        borderRadius: 20,
        onTap: () => setState(() => _color = c),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Color(c.argb),
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
          child: selected
              ? const Icon(Icons.check_rounded, color: Colors.black87, size: 18)
              : null,
        ),
      ),
    );
  }
}

/// Every highlight of the title, grouped by chapter.
class NovelHighlightsSheet extends StatefulWidget {
  const NovelHighlightsSheet({
    super.key,
    required this.load,
    required this.accent,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final List<NovelHighlight> Function() load;
  final Color accent;
  final ValueChanged<NovelHighlight> onOpen;
  final Future<void> Function(NovelHighlight) onEdit;
  final Future<void> Function(NovelHighlight) onDelete;

  @override
  State<NovelHighlightsSheet> createState() => _NovelHighlightsSheetState();
}

class _NovelHighlightsSheetState extends State<NovelHighlightsSheet> {
  late List<NovelHighlight> _items = widget.load();

  Future<void> _after(Future<void> action) async {
    await action;
    if (mounted) setState(() => _items = widget.load());
  }

  List<Object> get _rows {
    final rows = <Object>[];
    String? chapter;
    for (final h in _items) {
      final key = '${h.chapter}|${h.chapterRef}';
      if (key != chapter) {
        chapter = key;
        rows.add(h.chapterLabel);
      }
      rows.add(h);
    }
    return rows;
  }

  Widget _heading(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
    child: Text(
      label.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.9,
      ),
    ),
  );

  Widget _tile(NovelHighlight h) {
    final color = Color(h.color.argb);
    return InkWell(
      onTap: () => widget.onOpen(h),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 6, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 44,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    h.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                  if (h.note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        h.note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color.withValues(alpha: 0.85),
                          fontSize: 12.5,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'general.edit'.tr(),
              icon: const Icon(
                Icons.edit_note_rounded,
                color: Colors.white54,
                size: 20,
              ),
              onPressed: () => _after(widget.onEdit(h)),
            ),
            IconButton(
              tooltip: 'manga.remove_highlight'.tr(),
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.white54,
                size: 20,
              ),
              onPressed: () => _after(widget.onDelete(h)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(ScrollController? controller) {
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.border_color_outlined,
                color: Colors.white24,
                size: 36,
              ),
              const SizedBox(height: 12),
              Text(
                'manga.no_highlights'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
    final rows = _rows;
    return ListView.builder(
      controller: controller,
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        return row is NovelHighlight ? _tile(row) : _heading(row as String);
      },
    );
  }

  Widget _title() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Text(
      'manga.highlights'.tr(),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (isDesktopPlatform) {
      return SizedBox(
        width: 420,
        height: 480,
        child: Column(
          children: [
            _title(),
            Expanded(child: _list(null)),
          ],
        ),
      );
    }
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (context, scroll) => Column(
        children: [
          _title(),
          Expanded(child: _list(scroll)),
        ],
      ),
    );
  }
}
