import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soplay/core/theme/app_colors.dart';

class NetflixSplash extends StatefulWidget {
  const NetflixSplash({super.key, required this.onComplete});
  final VoidCallback onComplete;

  @override
  State<NetflixSplash> createState() => _NetflixSplashState();
}

class _NetflixSplashState extends State<NetflixSplash>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _sScale;
  late Animation<double> _sOpacity;
  late Animation<double> _oplayWidth;
  late Animation<double> _oplayOpacity;
  late Animation<double> _fadeOut;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.background,
      ),
    );
    _setup();
    _run();
  }

  void _setup() {
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3800),
    );

    _sScale = Tween<double>(begin: 0.04, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.30, curve: Cubic(0.19, 1.0, 0.22, 1.0)),
      ),
    );

    _sOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.10, curve: Curves.easeIn),
      ),
    );

    _oplayWidth = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.27, 0.62, curve: Cubic(0.42, 0.0, 0.58, 1.0)),
      ),
    );

    _oplayOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.27, 0.48, curve: Curves.easeIn),
      ),
    );

    _fadeOut = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.84, 1.0, curve: Curves.easeIn),
      ),
    );
  }

  Future<void> _run() async {
    await Future.delayed(const Duration(milliseconds: 500));
    await _controller.forward();
    widget.onComplete();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Opacity(
            opacity: _fadeOut.value,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Opacity(
                    opacity: _sOpacity.value,
                    child: Transform.scale(
                      scale: _sScale.value,
                      alignment: Alignment.center,
                      child: Text('S', style: _kStyle),
                    ),
                  ),
                  ClipRect(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: _oplayWidth.value,
                      child: Opacity(
                        opacity: _oplayOpacity.value,
                        child: Text('OZO', style: _kStyle),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A getter, not a `const`: the wordmark is painted in the accent colour, and
/// the accent is a runtime choice now.
TextStyle get _kStyle => TextStyle(
  color: AppColors.primary,
  fontSize: 80,
  fontWeight: FontWeight.w900,
  letterSpacing: -3.5,
  height: 1.0,
);
