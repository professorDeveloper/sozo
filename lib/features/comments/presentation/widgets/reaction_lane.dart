import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:soplay/features/comments/domain/timed_reactions.dart';

/// Other viewers' reactions as pills that fade in at their second and out a
/// few seconds later, in a column at the start edge of the video, clear of
/// the subtitles at the bottom and the controls along the edges.
class ReactionLane extends StatefulWidget {
  const ReactionLane({super.key, required this.pops});

  final ValueListenable<List<ReactionPop>> pops;

  @override
  State<ReactionLane> createState() => _ReactionLaneState();
}

class _ReactionLaneState extends State<ReactionLane> {
  static const Duration _fade = Duration(milliseconds: 280);

  /// On screen, including pills still fading out.
  final List<_Shown> _shown = [];

  @override
  void initState() {
    super.initState();
    widget.pops.addListener(_sync);
    _sync();
  }

  @override
  void didUpdateWidget(covariant ReactionLane old) {
    super.didUpdateWidget(old);
    if (old.pops != widget.pops) {
      old.pops.removeListener(_sync);
      widget.pops.addListener(_sync);
      _sync();
    }
  }

  @override
  void dispose() {
    widget.pops.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    final next = {for (final p in widget.pops.value) p.id: p};
    setState(() {
      for (final s in _shown) {
        final p = next.remove(s.pop.id);
        if (p != null) {
          s.pop = p;
          s.leaving = false;
        } else if (!s.leaving) {
          s.leaving = true;
          Future.delayed(_fade, () {
            if (!mounted) return;
            setState(() => _shown.removeWhere((x) => x.leaving && x == s));
          });
        }
      }
      for (final p in next.values) {
        _shown.add(_Shown(p));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in _shown)
            TweenAnimationBuilder<double>(
              key: ValueKey(s.pop.id),
              tween: Tween(begin: 0, end: s.leaving ? 0 : 1),
              duration: _fade,
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * 10),
                  child: child,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _Pill(pop: s.pop),
              ),
            ),
        ],
      ),
    );
  }
}

class _Shown {
  _Shown(this.pop);
  ReactionPop pop;
  bool leaving = false;
}

class _Pill extends StatelessWidget {
  const _Pill({required this.pop});

  final ReactionPop pop;

  @override
  Widget build(BuildContext context) {
    final emoji = pop.kind == 'emoji';
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: EdgeInsets.symmetric(horizontal: emoji ? 8 : 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              pop.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: emoji ? 20 : 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (pop.count > 1) ...[
            const SizedBox(width: 4),
            Text(
              '×${pop.count}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
