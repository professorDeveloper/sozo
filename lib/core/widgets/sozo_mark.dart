import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The Sozo mark, as vector.
///
/// One asset for every size the app draws it at. The shipped icon is a 512px
/// PNG with texture baked into it, which goes soft the moment it is scaled past
/// its own resolution — and the mode-switch animation below scales it a long
/// way past that.
///
/// The file paints in `currentColor`, so the colour comes from [color] here
/// rather than from the asset. That is what lets the same file serve a splash,
/// a switch animation and anything tinted by whatever accent the user picked,
/// instead of needing a copy per colour.
class SozoMark extends StatelessWidget {
  const SozoMark({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  static const String asset = 'assets/brand/sozo_mark.svg';

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        asset,
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
}
