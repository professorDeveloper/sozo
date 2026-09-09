import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/player/media_controller.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/trailer/trailer_query.dart';
import 'package:soplay/core/trailer/trailer_service.dart';

/// The title's trailer, playing in the header behind everything else.
///
/// ## What it does and when
///
/// The poster is what the page opens with and stays the whole time — this
/// draws over it, and only once there is something worth drawing. The order is
/// deliberate:
///
///  1. The page arrives and the poster is already correct.
///  2. The hero flight, if there was one, finishes.
///  3. A quiet delay, so somebody who opened this page to read the synopsis and
///     leave never sees a video start at all.
///  4. The trailer resolves and buffers, still invisible.
///  5. It cross-fades in, muted.
///
/// Nothing before step 5 changes a pixel. A preview that appears while the
/// poster is still travelling is the same defect as gradients arriving early —
/// motion competing with motion — and one that appears the instant the page
/// opens turns every tap into an unasked-for video.
///
/// ## Why muted, and why it stays that way unless asked
///
/// Sound that starts by itself is hostile on a phone: in a room with other
/// people, on a commute, at night. It starts muted and the speaker button is
/// the only way to change that. The choice is not remembered between titles
/// either — unmuting one trailer is not a standing instruction to play sound
/// on the next page somebody opens.
///
/// ## What stops it
///
/// Scrolling past the header, leaving the page, the app going to the
/// background, and the setting being turned off while it plays. A trailer that
/// keeps decoding under a page nobody is looking at is a battery drain the
/// viewer cannot see the cause of.
class HeroTrailerPreview extends StatefulWidget {
  const HeroTrailerPreview({
    super.key,
    required this.query,
    required this.active,
  });

  /// What to play, handed to the service rather than resolved here: the
  /// trailer button on the same page asks with the same value, and the service
  /// answers the second one from the first one's lookup.
  final TrailerQuery query;

  /// Whether the header is on screen. Driven by the page's scroll position, so
  /// the preview stops when it is scrolled away and resumes when it is not.
  final bool active;

  /// How long the page is left alone before anything is fetched.
  ///
  /// Long enough that opening a title, glancing at it and going back never
  /// costs a video request; short enough that somebody who stays gets the
  /// preview while still looking at the header.
  static const Duration startDelay = Duration(milliseconds: 2200);

  @override
  State<HeroTrailerPreview> createState() => _HeroTrailerPreviewState();
}

class _HeroTrailerPreviewState extends State<HeroTrailerPreview>
    with WidgetsBindingObserver {
  PlayerController? _controller;
  Timer? _startTimer;
  bool _visible = false;
  bool _muted = true;

  /// Guards against a resolve finishing after this page is gone, and against
  /// two starts racing when `active` flickers during a scroll.
  int _token = 0;

  HiveService get _hive => getIt<HiveService>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hive.heroTrailerAutoplayChanged.addListener(_onSettingChanged);
    _maybeSchedule();
  }

  @override
  void didUpdateWidget(covariant HeroTrailerPreview old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) {
      _teardown();
      _maybeSchedule();
      return;
    }
    if (old.active == widget.active) return;
    if (widget.active) {
      // Scrolled back to the header. Resume rather than start over: somebody
      // who scrolled down and back has already waited once.
      _controller?.play();
      _maybeSchedule();
    } else {
      _startTimer?.cancel();
      _controller?.pause();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (widget.active && _visible) _controller?.play();
    } else {
      _controller?.pause();
    }
  }

  void _onSettingChanged() {
    if (_hive.heroTrailerAutoplay) {
      _maybeSchedule();
    } else {
      _teardown();
    }
  }

  void _maybeSchedule() {
    if (_controller != null || _startTimer != null) return;
    // Named, because "the trailer never appears" has four possible causes and
    // three of them are silent gates. Without this the only way to tell a
    // switched-off setting from a scrolled-away header from a title TMDB does
    // not know is to read the source.
    if (!widget.active) {
      debugPrint('[trailer] not scheduled: header is not active');
      return;
    }
    if (!_hive.heroTrailerAutoplay) {
      debugPrint('[trailer] not scheduled: autoplay is off in settings');
      return;
    }

    _startTimer = Timer(HeroTrailerPreview.startDelay, () {
      _startTimer = null;
      unawaited(_start());
    });
  }

  Future<void> _start() async {
    if (!mounted || !widget.active) return;

    final token = ++_token;
    final trailer = await getIt<TrailerService>().resolveFor(widget.query);
    if (trailer == null) {
      // The fourth cause: TMDB has no trailer for this title, or has no record
      // of the title at all — which is the normal answer for the Uzbek
      // catalogues, whose names TMDB has never heard.
      debugPrint('[trailer] no trailer for "${widget.query.title}"');
      return;
    }
    if (!mounted || token != _token || !widget.active) return;

    PlayerController? controller;
    try {
      controller = PlayerController.networkUrl(Uri.parse(trailer.streamUrl));
      await controller.initialize();
      if (!mounted || token != _token || !widget.active) {
        await controller.dispose();
        return;
      }
      await controller.setVolume(0);
      await controller.setLooping(true);
      await controller.play();
      _controller = controller;
      // Painted only now: the frames before this are black, and a black
      // rectangle appearing over the poster is worse than no preview.
      setState(() => _visible = true);
    } catch (e) {
      // Still nothing shown: the poster is there and nothing was promised. But
      // the reason is written down now. A resolved, fetchable stream that will
      // not initialise is the signature of a device that cannot render video
      // at all — which is what an emulator without a GPU path looks like, and
      // it is indistinguishable from a broken feature without this line.
      debugPrint('[trailer] resolved but would not play: $e');
      await controller?.dispose();
    }
  }

  void _teardown() {
    _token++;
    _startTimer?.cancel();
    _startTimer = null;
    final c = _controller;
    _controller = null;
    if (mounted && _visible) setState(() => _visible = false);
    unawaited(c?.dispose());
  }

  void _toggleMute() {
    final c = _controller;
    if (c == null) return;
    setState(() => _muted = !_muted);
    unawaited(c.setVolume(_muted ? 0 : 1));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hive.heroTrailerAutoplayChanged.removeListener(_onSettingChanged);
    _startTimer?.cancel();
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !_visible) return const SizedBox.shrink();

    return Stack(
      fit: StackFit.expand,
      children: [
        // Cross-fades in over the poster rather than replacing it. The poster
        // stays underneath for the whole preview, so a trailer that stalls or
        // ends leaves the page looking exactly as it did before.
        AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOut,
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: controller.buildView(),
            ),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: _MuteButton(muted: _muted, onTap: _toggleMute),
        ),
      ],
    );
  }
}

/// The one control a preview gets.
///
/// Small and low-contrast on purpose: it sits over artwork, and the trailer is
/// something the page is offering rather than something it is asking about.
class _MuteButton extends StatelessWidget {
  const _MuteButton({required this.muted, required this.onTap});

  final bool muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: muted ? 'detail.trailer_unmute'.tr() : 'detail.trailer_mute'.tr(),
      child: Material(
        color: Colors.black.withValues(alpha: 0.42),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(
              muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              size: 17,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
