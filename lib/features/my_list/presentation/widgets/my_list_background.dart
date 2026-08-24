import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';

class MyListBackground extends StatelessWidget {
  const MyListBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          // The old literals were #161616 and #101010 — a shade under the
          // background and the same fall-off Profile's backdrop uses. Derived
          // now, so the page goes true black with everything else instead of
          // staying a grey slab.
          colors: [
            Color.lerp(AppColors.background, Colors.black, 0.083)!,
            AppColors.background,
            AppColors.heroBottom,
          ],
          stops: const [0, 0.42, 1],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}
