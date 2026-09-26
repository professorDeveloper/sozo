import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/app_buttons.dart';
import 'package:soplay/features/achievements/domain/achievements.dart';
import 'package:soplay/features/achievements/presentation/widgets/achievement_medal.dart';
import 'package:soplay/features/home_widget/home_widget_sync.dart';
import 'package:soplay/features/onboarding/domain/onboarding_flow.dart';
import 'package:soplay/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:soplay/features/onboarding/presentation/onboarding_navigation.dart';
import 'package:soplay/features/onboarding/presentation/widgets/kind_style.dart';
import 'package:soplay/features/onboarding/presentation/widgets/onboarding_focus_button.dart';
import 'package:soplay/features/onboarding/presentation/widgets/onboarding_scaffold.dart';

/// The home-screen widgets, shown on a home screen of their own, with a button
/// that asks the launcher to add each one — Android's own "add to home
/// screen" sheet, no hunting through the widget list.
class OnboardingWidgetsPage extends StatefulWidget {
  const OnboardingWidgetsPage({super.key});

  @override
  State<OnboardingWidgetsPage> createState() => _OnboardingWidgetsPageState();
}

class _OnboardingWidgetsPageState extends State<OnboardingWidgetsPage>
    with WidgetsBindingObserver {
  final HomeWidgetSync _widgets = getIt<HomeWidgetSync>();
  final OnboardingController _c = getIt<OnboardingController>();

  /// Null until the launcher has said whether it takes widgets from the app.
  bool? _canPin;
  Map<String, int> _placed = const {};
  Timer? _watch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    final can = await _widgets.canPin();
    final placed = await _widgets.placed();
    if (!mounted) return;
    setState(() {
      _canPin = can;
      _placed = placed;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPlaced();
  }

  Future<void> _refreshPlaced() async {
    final placed = await _widgets.placed();
    if (mounted) setState(() => _placed = placed);
  }

  bool _isPlaced(String kind) => (_placed[kind] ?? 0) > 0;

  Future<void> _pin(String kind) async {
    final asked = await _widgets.pin(kind);
    if (!asked || !mounted) return;
    // The launcher's sheet is its own window; the app is not always paused
    // under it. Look for the widget for a while rather than waiting on a
    // resume that may not come.
    _watch?.cancel();
    var ticks = 0;
    _watch = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (++ticks > 30) timer.cancel();
      await _refreshPlaced();
      if (_isPlaced(kind)) timer.cancel();
    });
  }

  @override
  void dispose() {
    _watch?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final can = _canPin;
    final posters = postersFor(_c.kinds, count: 4);
    return OnboardingScaffold(
      step: OnboardingStep.widgets,
      maxBodyWidth: 520,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          children: [
            _HomeScreen(
              posters: posters,
              streakPlaced: _isPlaced('streak'),
              continuePlaced: _isPlaced('continue'),
            ),
            const SizedBox(height: 24),
            OnboardingHeading(
              center: true,
              title: 'onboarding.widgets_title'.tr(),
              subtitle: 'onboarding.widgets_body'.tr(),
            ),
            if (can == false) ...[
              const SizedBox(height: 14),
              _Hint(text: 'onboarding.widgets_manual'.tr()),
            ],
          ],
        ),
      ),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (can == true) ...[
            OnboardingFocusButton(
              autofocus: true,
              child: AppPrimaryButton(
                label: _isPlaced('streak')
                    ? 'onboarding.widgets_added'.tr()
                    : 'onboarding.widgets_add_streak'.tr(),
                icon: _isPlaced('streak')
                    ? Icons.check_rounded
                    : Icons.local_fire_department_rounded,
                onPressed: _isPlaced('streak') ? null : () => _pin('streak'),
              ),
            ),
            const SizedBox(height: 10),
            OnboardingFocusButton(
              child: AppSecondaryButton(
                label: _isPlaced('continue')
                    ? 'onboarding.widgets_added'.tr()
                    : 'onboarding.widgets_add_continue'.tr(),
                icon: _isPlaced('continue')
                    ? Icons.check_rounded
                    : Icons.play_circle_outline_rounded,
                onPressed: _isPlaced('continue')
                    ? null
                    : () => _pin('continue'),
              ),
            ),
            const SizedBox(height: 4),
            OnboardingFocusButton(
              child: TextButton(
                onPressed: () => onboardingNext(context),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  minimumSize: const Size(0, 44),
                ),
                child: Text(
                  _placed.values.any((n) => n > 0)
                      ? 'onboarding.continue'.tr()
                      : 'onboarding.widgets_later'.tr(),
                ),
              ),
            ),
          ] else
            OnboardingFocusButton(
              autofocus: true,
              child: AppPrimaryButton(
                label: 'onboarding.continue'.tr(),
                onPressed: () => onboardingNext(context),
              ),
            ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.touch_app_rounded,
            color: Colors.white.withValues(alpha: 0.7),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: OnbType.small,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A phone's home screen with the widgets on it, dropping into place one by
/// one, the next to add breathing a ring.
class _HomeScreen extends StatefulWidget {
  const _HomeScreen({
    required this.posters,
    required this.streakPlaced,
    required this.continuePlaced,
  });

  final List<String> posters;
  final bool streakPlaced;
  final bool continuePlaced;

  @override
  State<_HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<_HomeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _arrive = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _arrive.value = 1;
      _pulse.stop();
    } else {
      if (_arrive.value == 0) _arrive.forward();
      if (!_pulse.isAnimating) _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _arrive.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Widget _drop(int i, Widget child) {
    return AnimatedBuilder(
      animation: _arrive,
      child: child,
      builder: (context, child) {
        final v = Curves.easeOutCubic.transform(
          ((_arrive.value - 0.18 * i) / 0.55).clamp(0.0, 1.0),
        );
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, (1 - v) * 26),
            child: Transform.scale(scale: 0.92 + 0.08 * v, child: child),
          ),
        );
      },
    );
  }

  Widget _ring({required bool on, required Widget child}) {
    if (!on) return child;
    return AnimatedBuilder(
      animation: _pulse,
      child: child,
      builder: (context, child) {
        final v = math.sin(_pulse.value * math.pi);
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18 + 0.4 * v),
              width: 1.5,
            ),
          ),
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final posters = widget.posters;
    String poster(int i) => posters.isEmpty ? '' : posters[i % posters.length];
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, box) {
          final width = math.min(box.maxWidth, 360.0);
          const pad = 14.0;
          const gap = 12.0;
          // What is left inside the card's 1 px border and its padding.
          final inner = width - 2 - pad * 2;
          final cell = (inner - gap) / 2;
          // The same card as the rest of the setup — its surface, its
          // hairline border, no shadow — so the widgets are what stands out,
          // not a slab of their own.
          return Container(
            width: width,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0x1AFFFFFF)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(pad, 16, pad, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      _drop(
                        0,
                        _ring(
                          on: !widget.streakPlaced,
                          child: _StreakMock(size: cell),
                        ),
                      ),
                      const SizedBox(width: gap),
                      _drop(1, _PosterMock(size: cell, asset: poster(0))),
                    ],
                  ),
                  const SizedBox(height: gap),
                  _drop(
                    2,
                    _ring(
                      on: widget.streakPlaced && !widget.continuePlaced,
                      child: _ContinueMock(
                        width: inner,
                        posters: [poster(1), poster(2), poster(3)],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _drop(
                    3,
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Themed, monochrome icons: the dock without a
                        // rainbow in it pulling the eye off the widgets.
                        for (final icon in const [
                          Icons.call_rounded,
                          Icons.chat_bubble_rounded,
                          Icons.photo_camera_rounded,
                          Icons.language_rounded,
                        ])
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(
                              icon,
                              size: 19,
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                      ],
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

const _widgetBg = Color(0xF2181818);

/// The streak widget as the launcher draws it.
class _StreakMock extends StatelessWidget {
  const _StreakMock({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    const lit = [true, true, false, true, true, true, false];
    const days = [
      'streak.weekday_sat',
      'streak.weekday_sun',
      'streak.weekday_mon',
      'streak.weekday_tue',
      'streak.weekday_wed',
      'streak.weekday_thu',
      'streak.weekday_fri',
    ];
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(10),
      // The widget's dark card with the flame's warmth from its middle.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const RadialGradient(
          center: Alignment(0, 0.1),
          radius: 0.85,
          colors: [Color(0xFF3A2317), Color(0xFF161210)],
        ),
      ),
      child: FittedBox(
        child: SizedBox(
          width: 150,
          height: 150,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const AchievementBadge(
                id: 'streak',
                tier: MedalTier.locked,
                size: 58,
                progress: 4 / 7,
                showLock: false,
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    '4',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      'home_widget.streak_days'.tr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFFFC078),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 7; i++)
                    SizedBox(
                      width: 16,
                      child: Column(
                        children: [
                          _Dot(on: lit[i], today: i == 6),
                          const SizedBox(height: 2),
                          Text(
                            days[i].tr().characters.first,
                            style: TextStyle(
                              color: Colors.white.withValues(
                                alpha: i == 6 ? 1 : 0.5,
                              ),
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'home_widget.streak_next'.tr(
                  namedArgs: {'left': '3', 'target': '7'},
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.on, required this.today});

  final bool on;
  final bool today;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: on
            ? const LinearGradient(
                colors: [Color(0xFFFFC078), Color(0xFFEF7A35)],
              )
            : null,
        color: on
            ? null
            : today
            ? Colors.transparent
            : Colors.white.withValues(alpha: 0.18),
        border: today && !on
            ? Border.all(color: const Color(0xFFFFA64D), width: 1.4)
            : null,
      ),
    );
  }
}

/// The small Continue widget: one poster, the episode, the progress.
class _PosterMock extends StatelessWidget {
  const _PosterMock({required this.size, required this.asset});

  final double size;
  final String asset;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (asset.isNotEmpty)
              Image.asset(asset, fit: BoxFit.cover, cacheWidth: 360)
            else
              const ColoredBox(color: _widgetBg),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.45, 1],
                  colors: [Color(0x00000000), Color(0xDD000000)],
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0x99000000),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      size: 11,
                      color: Color(0xFFFFA64D),
                    ),
                    SizedBox(width: 2),
                    Text(
                      '4',
                      style: TextStyle(
                        color: Color(0xFFFFA64D),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'home_widget.episode'.tr(args: ['5']),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const _Progress(value: 0.4),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The wide Continue widget: three posters and what airs next.
class _ContinueMock extends StatelessWidget {
  const _ContinueMock({required this.width, required this.posters});

  final double width;
  final List<String> posters;

  @override
  Widget build(BuildContext context) {
    const progress = [0.62, 0.3, 0.85];
    final labels = [
      'home_widget.episode'.tr(args: ['12']),
      'home_widget.chapter'.tr(args: ['48']),
      'home_widget.episode'.tr(args: ['3']),
    ];
    return Container(
      width: width,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _widgetBg,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (posters[i].isNotEmpty)
                                Image.asset(
                                  posters[i],
                                  fit: BoxFit.cover,
                                  cacheWidth: 240,
                                )
                              else
                                ColoredBox(
                                  color: Colors.white.withValues(alpha: 0.06),
                                ),
                              Positioned(
                                left: 6,
                                right: 6,
                                bottom: 6,
                                child: _Progress(value: progress[i]),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        labels[i],
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  size: 13,
                  color: Color(0xFF7FB2FF),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'home_widget.next'.tr(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 11,
                    ),
                  ),
                ),
                Text(
                  '${'home_widget.d'.tr(args: ['2'])} ${'home_widget.h'.tr(args: ['4'])}',
                  style: const TextStyle(
                    color: Color(0xFF7FB2FF),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.white.withValues(alpha: 0.25)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value,
              child: const ColoredBox(color: Color(0xFFE5484D)),
            ),
          ],
        ),
      ),
    );
  }
}
