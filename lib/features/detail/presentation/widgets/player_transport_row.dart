import 'package:flutter/material.dart';

/// Episode navigation stays outside the two seek buttons, including at either
/// end of a series. Empty slots keep play/pause at the centre of the screen.
class PlayerTransportRow extends StatelessWidget {
  const PlayerTransportRow({
    super.key,
    this.previous,
    this.next,
    required this.rewind,
    required this.playPause,
    required this.forward,
  });

  final Widget? previous;
  final Widget? next;
  final Widget rewind;
  final Widget playPause;
  final Widget forward;

  @override
  Widget build(BuildContext context) {
    final episodes = previous != null || next != null;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: episodes ? 420 : 280),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            // Transport has physical direction even in an RTL interface.
            textDirection: TextDirection.ltr,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (episodes) previous ?? const SizedBox(width: 52),
              rewind,
              playPause,
              forward,
              if (episodes) next ?? const SizedBox(width: 52),
            ],
          ),
        ),
      ),
    );
  }
}
