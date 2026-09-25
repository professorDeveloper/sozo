import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';

class PinDots extends StatefulWidget {
  const PinDots({
    super.key,
    required this.length,
    required this.filled,
    required this.errorTick,
  });

  final int length;
  final int filled;
  final int errorTick;

  @override
  State<PinDots> createState() => _PinDotsState();
}

class _PinDotsState extends State<PinDots> with SingleTickerProviderStateMixin {
  late final AnimationController _shake;
  late Animation<double> _offset;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _offset = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -10), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10, end: -8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8, end: 6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shake, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(covariant PinDots old) {
    super.didUpdateWidget(old);
    if (old.errorTick != widget.errorTick && widget.errorTick > 0) {
      _shake.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shake,
      builder: (_, _) {
        final showError = _shake.status == AnimationStatus.forward;
        return Transform.translate(
          offset: Offset(_offset.value, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(widget.length, (i) {
              final isFilled = i < widget.filled;
              final color = showError
                  ? AppColors.error
                  : isFilled
                  ? AppColors.primary
                  : AppColors.border;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: isFilled ? 16 : 14,
                height: isFilled ? 16 : 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isFilled ? color : Colors.transparent,
                  border: Border.all(color: color, width: 1.6),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
