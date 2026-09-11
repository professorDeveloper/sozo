import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:soplay/core/theme/kaizoku_colors.dart';
import 'package:soplay/features/watch_party/data/watch_party_service.dart';
import 'package:soplay/features/watch_party/domain/entities/party_reaction.dart';

const List<String> kPartyReactions = ['❤️', '😂', '😮', '👏', '🔥', '😍', '🎉'];

/// Full-bleed, display-only layer that floats incoming reactions up over the
/// video. Own reactions arrive instantly via the service's optimistic echo.
/// Safe to place anywhere in a Stack — it ignores pointers.
class PartyReactionsOverlay extends StatefulWidget {
  const PartyReactionsOverlay({super.key, required this.service});

  final WatchPartyService service;

  @override
  State<PartyReactionsOverlay> createState() => _PartyReactionsOverlayState();
}

class _PartyReactionsOverlayState extends State<PartyReactionsOverlay> {
  static const int _maxFloaters = 40; // concurrency cap for low-end devices

  final math.Random _rng = math.Random();
  final List<_Floater> _floaters = [];
  StreamSubscription<PartyReaction>? _sub;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _sub = widget.service.reactions.listen(_spawn);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _spawn(PartyReaction r) {
    if (!mounted || r.emoji.isEmpty) return;
    setState(() {
      if (_floaters.length >= _maxFloaters) _floaters.removeAt(0);
      _floaters.add(_Floater.random(_seq++, r.emoji, _rng));
    });
  }

  void _remove(int id) {
    if (!mounted) return;
    setState(() => _floaters.removeWhere((f) => f.id == id));
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, c) => Stack(
          children: [
            for (final f in _floaters)
              _FloatingEmoji(
                key: ValueKey(f.id),
                floater: f,
                width: c.maxWidth,
                height: c.maxHeight.isFinite ? c.maxHeight : 200,
                onDone: () => _remove(f.id),
              ),
          ],
        ),
      ),
    );
  }
}

/// Compact emoji picker row that sends reactions.
class PartyReactionPicker extends StatelessWidget {
  const PartyReactionPicker({super.key, required this.service});

  final WatchPartyService service;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: KaizokuColors.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: KaizokuColors.cardBorder, width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in kPartyReactions)
            _EmojiButton(emoji: e, onTap: () => service.sendReaction(e)),
        ],
      ),
    );
  }
}

/// Lobby widget: the floating overlay + a centered picker in a fixed box.
class PartyReactionsBar extends StatelessWidget {
  const PartyReactionsBar({super.key, required this.service});

  final WatchPartyService service;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: Stack(
        children: [
          Positioned.fill(child: PartyReactionsOverlay(service: service)),
          Align(
            alignment: Alignment.bottomCenter,
            child: PartyReactionPicker(service: service),
          ),
        ],
      ),
    );
  }
}

class _Floater {
  _Floater({
    required this.id,
    required this.emoji,
    required this.startX,
    required this.driftX,
    required this.riseFraction,
    required this.durationMs,
    required this.size,
    required this.rotation,
  });

  final int id;
  final String emoji;
  final double startX; // 0..1 horizontal start
  final double driftX; // px horizontal drift over the rise
  final double riseFraction; // 0..1 of container height to travel
  final int durationMs;
  final double size;
  final double rotation; // max radians

  factory _Floater.random(int id, String emoji, math.Random r) => _Floater(
        id: id,
        emoji: emoji,
        startX: 0.12 + r.nextDouble() * 0.72,
        driftX: (r.nextDouble() - 0.5) * 90,
        riseFraction: 0.55 + r.nextDouble() * 0.38,
        durationMs: 1800 + r.nextInt(1100),
        size: 24 + r.nextDouble() * 12,
        rotation: (r.nextDouble() - 0.5) * 0.6,
      );
}

class _EmojiButton extends StatelessWidget {
  const _EmojiButton({required this.emoji, required this.onTap});

  final String emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(emoji, style: const TextStyle(fontSize: 22)),
      ),
    );
  }
}

class _FloatingEmoji extends StatefulWidget {
  const _FloatingEmoji({
    super.key,
    required this.floater,
    required this.width,
    required this.height,
    required this.onDone,
  });

  final _Floater floater;
  final double width;
  final double height;
  final VoidCallback onDone;

  @override
  State<_FloatingEmoji> createState() => _FloatingEmojiState();
}

class _FloatingEmojiState extends State<_FloatingEmoji>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.floater.durationMs),
  );

  @override
  void initState() {
    super.initState();
    _c.addStatusListener(_onStatus);
    _c.forward();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) widget.onDone();
  }

  @override
  void dispose() {
    _c.removeStatusListener(_onStatus);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.floater;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        final rise = widget.height * f.riseFraction;
        final bottom = 20 + t * rise;
        // Ease out-and-back horizontal drift for a gentle sway.
        final drift = math.sin(t * math.pi) * f.driftX;
        final left = f.startX * (widget.width - 40) + drift;
        // Fade in fast, hold, fade out over the last third.
        final opacity = t < 0.12
            ? t / 0.12
            : (t > 0.66 ? (1 - (t - 0.66) / 0.34) : 1.0);
        // Pop in (0.6 -> 1.1) then settle to 1.0.
        final scale = t < 0.2
            ? 0.6 + (t / 0.2) * 0.5
            : 1.1 - ((t - 0.2) / 0.8) * 0.1;
        return Positioned(
          left: left,
          bottom: bottom,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.rotate(
              angle: f.rotation * t,
              child: Transform.scale(scale: scale, child: child),
            ),
          ),
        );
      },
      child: Text(f.emoji, style: TextStyle(fontSize: f.size)),
    );
  }
}
