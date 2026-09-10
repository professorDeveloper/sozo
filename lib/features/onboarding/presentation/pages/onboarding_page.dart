import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/localization/language_picker.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/auth/data/services/google_auth_service.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_event.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_state.dart';
import 'package:soplay/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:soplay/features/onboarding/data/onboarding_posters.dart';
import 'package:soplay/features/onboarding/presentation/widgets/anime_ribbons.dart';
import 'package:soplay/features/onboarding/presentation/widgets/tv_showcase.dart';
import 'package:soplay/features/onboarding/presentation/widgets/poster_wall.dart';

/// The signed-out landing screen.
///
/// Each slide brings its own backdrop rather than re-colouring one: films fall
/// in columns, anime slides across in shelves, and the third names what the app
/// does besides play a file. Three slides over one background would just be
/// three captions.
///
/// The sign-in options sit under all of it the whole time, so nobody has to
/// page through the story to reach them.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  static const _slides = 3;

  final _pageController = PageController();
  int _page = 0;
  bool _googlePending = false;
  bool _languageConfirmed = false;
  bool _leaving = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Marked on the way out rather than on entry: a first launch killed halfway
  /// through should still get the introduction next time.
  Future<void> _leave(String route) async {
    if (_leaving) return;
    _leaving = true;
    if (!_languageConfirmed) {
      _languageConfirmed = await confirmIntroLanguage(context);
      if (!mounted || !_languageConfirmed) {
        _leaving = false;
        return;
      }
    }
    await getIt<HiveService>().markOnboardingSeen();
    if (!mounted) return;
    context.go(route);
  }

  Future<void> _continueWithGoogle() async {
    if (_leaving || _googlePending) return;
    _leaving = true;
    if (!_languageConfirmed) {
      _languageConfirmed = await confirmIntroLanguage(context);
    }
    _leaving = false;
    if (!mounted || !_languageConfirmed) return;
    setState(() => _googlePending = true);
    context.read<AuthBloc>().add(const AuthGoogleRequested());
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthLoaded) {
          _leave('/main');
        } else if (state is AuthError) {
          setState(() => _googlePending = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppColors.error,
            ),
          );
        } else if (state is AuthInitial) {
          setState(() => _googlePending = false);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _Backdrops(controller: _pageController, page: _page),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  // The last two stops are the page background arriving — the
                  // third used to be the literal #181818, which under AMOLED
                  // left the poster fading into grey and then jumping to black.
                  colors: [
                    const Color(0xB3000000),
                    const Color(0x33000000),
                    AppColors.background.withValues(alpha: 0.949),
                    AppColors.background,
                  ],
                  stops: const [0, 0.28, 0.62, 0.8],
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: SizedBox(
                    height: constraints.maxHeight.clamp(
                      540 +
                          (MediaQuery.textScalerOf(context).scale(14) - 14) *
                              32,
                      double.infinity,
                    ),
                    child: Column(
                      children: [
                        OnboardingHeader(onSkip: () => _leave('/main')),
                        Expanded(
                          child: PageView.builder(
                            controller: _pageController,
                            itemCount: _slides,
                            onPageChanged: (i) => setState(() => _page = i),
                            itemBuilder: (context, i) =>
                                _Slide(index: i, controller: _pageController),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _Dots(count: _slides, active: _page),
                        const SizedBox(height: 26),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: BlocBuilder<AuthBloc, AuthState>(
                            builder: (context, state) {
                              final loading = state is AuthLoading;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (GoogleAuthService.isSupported) ...[
                                    GoogleAuthButton(
                                      loading: loading && _googlePending,
                                      onPressed: loading
                                          ? null
                                          : _continueWithGoogle,
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                  FilledButton(
                                    onPressed: loading
                                        ? null
                                        : () => _leave('/register'),
                                    child: Text(
                                      'onboarding.continue_with_email'.tr(),
                                    ),
                                  ),
                                  AuthSwitchPrompt(
                                    text: 'auth.already_have_account'.tr(),
                                    action: 'auth.sign_in'.tr(),
                                    onTap: () => _leave('/login'),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OnboardingHeader extends StatelessWidget {
  const OnboardingHeader({super.key, required this.onSkip});

  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      // This single-line brand bar must stay stable; the page copy and buttons
      // below still use the user's full text scale.
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Padding(
        // Keeps both controls on their own edges, clear of the status bar.
        padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 12, 0),
        child: Row(
          children: [
            Text(
              'SOZO',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                height: 1,
              ),
            ),
            const Spacer(),
            _SkipChip(onTap: onSkip),
          ],
        ),
      ),
    );
  }
}

/// A quiet secondary action anchored to the top-right of the intro.
class _SkipChip extends StatelessWidget {
  const _SkipChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'onboarding.skip'.tr(),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 2),
          const Icon(Icons.chevron_right_rounded, size: 18),
        ],
      ),
    );
  }
}

/// Cross-fades the three backdrops against the swipe itself, so the artwork
/// changes with the finger rather than snapping when the page settles.
class _Backdrops extends StatelessWidget {
  const _Backdrops({required this.controller, required this.page});

  final PageController controller;
  final int page;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // `page` is null until the first layout, and the int index is the only
        // truth available then.
        final position =
            controller.hasClients && controller.position.haveDimensions
            ? controller.page ?? page.toDouble()
            : page.toDouble();

        return Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < 3; i++)
              if (1 - (position - i).abs() > 0.01)
                Opacity(
                  key: ValueKey(i),
                  opacity: (1 - (position - i).abs()).clamp(0.0, 1.0),
                  // Eases forward as it takes focus — a straight cross-fade
                  // between two full-screen walls reads as a glitch.
                  // Built only while it is on screen: the mosaic plays a
                  // one-shot entrance, and creating it up front would spend it
                  // behind two other slides.
                  child: Transform.scale(
                    scale: 1 + (position - i).abs() * 0.06,
                    child: switch (i) {
                      0 => const PosterWall(posters: kMoviePosters),
                      1 => const AnimeRibbons(),
                      _ => const TvShowcase(),
                    },
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({required this.index, required this.controller});

  final int index;
  final PageController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final position =
            controller.hasClients && controller.position.haveDimensions
            ? controller.page ?? index.toDouble()
            : index.toDouble();
        final distance = (position - index).abs().clamp(0.0, 1.0);
        // Fades out faster than it slides, so two captions are never both
        // legible at once mid-swipe.
        return Opacity(
          opacity: (1 - distance * 1.6).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset((position - index) * 46, distance * 10),
            child: child,
          ),
        );
      },
      child: _SlideBody(index: index),
    );
  }
}

class _SlideBody extends StatelessWidget {
  const _SlideBody({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Bottom-aligned inside a full-height page: the pager owns the whole
      // area so a drag anywhere on the artwork turns the slide, and the copy
      // still sits where it did.
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            'onboarding.slide_${index + 1}_title'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'onboarding.slide_${index + 1}_body'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            height: 6,
            width: i == active ? 20 : 6,
            decoration: BoxDecoration(
              color: i == active ? AppColors.primary : AppColors.border,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}
