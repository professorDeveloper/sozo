import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'package:soplay/core/theme/app_colors.dart';

/// The listening dialog: a live waveform, the words as they are heard, and one
/// way out.
///
/// The waveform is drawn from the recogniser's own sound level, not from a
/// timer. That distinction is the whole point of having one: a decorative
/// animation keeps dancing when the microphone has stopped hearing anything,
/// which is exactly the moment the user needs to be told. Bars that go flat
/// when someone stops talking — or when the phone is not picking them up —
/// answer "is it hearing me?" without a word of copy.
///
/// The level scale differs between Android and iOS (iOS reports decibels,
/// Android something undocumented), so nothing here assumes a range. A running
/// peak normalises whatever arrives, which also adapts to a quiet room and a
/// loud one without a calibration step.
///
/// Returns the final transcript, or null if the user backed out.
class VoiceSearchDialog extends StatefulWidget {
  const VoiceSearchDialog._({required this.speech, required this.onPartial});

  final SpeechToText speech;

  /// Fires for every partial result so the field behind the dialog fills in
  /// alongside it — closing then feels like the search was already there.
  final ValueChanged<String> onPartial;

  static Future<String?> show(
    BuildContext context, {
    required SpeechToText speech,
    required ValueChanged<String> onPartial,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => VoiceSearchDialog._(speech: speech, onPartial: onPartial),
    );
  }

  @override
  State<VoiceSearchDialog> createState() => _VoiceSearchDialogState();
}

class _VoiceSearchDialogState extends State<VoiceSearchDialog>
    with SingleTickerProviderStateMixin {
  /// How many bars the strip holds. Enough to read as a waveform, few enough
  /// that each one is still wide enough to see on a phone.
  static const int _barCount = 34;

  final List<double> _levels = List<double>.filled(_barCount, 0);

  late final AnimationController _ticker;

  /// Where the newest sample is heading; bars ease toward it so a single loud
  /// syllable does not make the strip flicker.
  double _target = 0;

  /// Running peak used to normalise, since the platforms disagree on scale.
  /// Never allowed to reach zero, which would divide the strip by nothing.
  double _peak = 1;

  String _words = '';
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_advance);
    _ticker.repeat();
    _start();
  }

  Future<void> _start() async {
    try {
      await _listen();
    } catch (e) {
      // A recogniser that refuses to start — no permission, no service, another
      // app holding the microphone. Closing beats a dialog with a flat
      // waveform that never explains itself.
      debugPrint('[voice] could not start listening: $e');
      if (mounted && !_done) _finish('');
    }
  }

  Future<void> _listen() async {
    await widget.speech.listen(
      onResult: (r) {
        final words = r.recognizedWords.trim();
        if (mounted && words.isNotEmpty) {
          setState(() => _words = words);
          widget.onPartial(words);
        }
        if (r.finalResult) _finish(words);
      },
      onSoundLevelChange: (level) {
        // Absolute value: iOS reports negative decibels, Android does not.
        final v = level.abs();
        if (v > _peak) _peak = v;
        // Decay the peak slowly so one loud noise does not flatten the strip
        // for the rest of the session.
        _peak = math.max(1, _peak * 0.995);
        _target = (v / _peak).clamp(0.0, 1.0);
      },
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 3),
      ),
    );
    // NOT the end of the session.
    //
    // `listen()` completes as soon as the platform has STARTED listening — it
    // stamps the start time, arms its pause timers and returns. Treating that
    // as the end closed this dialog on the frame it opened, with an empty
    // transcript, while the recogniser carried on running: the microphone
    // indicator lit up and no dialog was ever visible.
    //
    // The session ends when a final result arrives (handled in onResult), when
    // the user stops it, or when the recogniser gives up on its own — and the
    // last of those is only observable through `isListening`, which [_advance]
    // already watches on every frame.
    //
    // A start that never happens is the other failure. `listen()` can return
    // without the platform ever entering the listening state, and the watchdog
    // in [_advance] only fires once it has seen listening begin — so without
    // this the dialog would wait forever on a microphone that was never opened.
    Future<void>.delayed(_startDeadline, () {
      if (mounted && !_done && !_everListened) {
        debugPrint('[voice] the recogniser never started listening');
        _finish('');
      }
    });
  }

  /// How long to wait for the microphone to actually open before giving up.
  ///
  /// Generous, because a cold recogniser on a slow device genuinely takes a
  /// second or two, and closing on somebody who was about to be heard is worse
  /// than a moment of blank waveform.
  static const Duration _startDeadline = Duration(seconds: 6);

  /// Whether the recogniser has actually started. Until it has, `isListening`
  /// is false for an ordinary reason and must not be read as "it stopped".
  bool _everListened = false;

  /// Shift the strip one step and ease the newest bar toward the live level.
  ///
  /// Also the session watchdog. The recogniser can end on its own — the
  /// `listenFor` ceiling, a `pauseFor` silence, a permanent error — and none of
  /// those calls back into this dialog. Without noticing, the dialog would sit
  /// over a dead microphone until somebody dismissed it.
  void _advance() {
    if (!mounted) return;
    if (widget.speech.isListening) {
      _everListened = true;
    } else if (_everListened && !_done) {
      // Ended by itself. Whatever was heard is the answer; nothing is the
      // answer too, and _finish turns that into a dismissal.
      _finish(_words);
      return;
    }
    for (var i = 0; i < _barCount - 1; i++) {
      _levels[i] = _levels[i + 1];
    }
    final last = _levels[_barCount - 1];
    _levels[_barCount - 1] = last + (_target - last) * 0.35;
    // Decay toward silence, so the strip settles flat when nothing is arriving
    // rather than holding the last value forever.
    _target *= 0.92;
    setState(() {});
  }

  void _finish(String words) {
    if (_done) return;
    _done = true;
    if (!mounted) return;
    Navigator.of(context).pop(words.isEmpty ? null : words);
  }

  Future<void> _stop() async {
    // stop() asks for a final result; cancel() would throw away the words
    // already on screen, which is not what a Done button means.
    await widget.speech.stop();
    if (mounted && !_done) _finish(_words);
  }

  @override
  void dispose() {
    _ticker.dispose();
    if (widget.speech.isListening) widget.speech.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listening = widget.speech.isListening;
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              listening ? Icons.mic_rounded : Icons.mic_off_rounded,
              size: 30,
              color: listening ? AppColors.primary : AppColors.textHint,
            ),
            const SizedBox(height: 14),
            Text(
              listening ? 'search.voice_listening'.tr() : 'search.voice_done'.tr(),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 56,
              width: double.infinity,
              child: CustomPaint(
                painter: _WavePainter(
                  levels: _levels,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 18),
            // Reserves its own height so the dialog does not jump the moment
            // the first word arrives.
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Center(
                child: Text(
                  _words.isEmpty ? 'search.voice_hint'.tr() : _words,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: _words.isEmpty ? 13 : 16,
                    fontWeight:
                        _words.isEmpty ? FontWeight.w400 : FontWeight.w600,
                    color: _words.isEmpty
                        ? AppColors.textHint
                        : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    widget.speech.cancel();
                    Navigator.of(context).pop();
                  },
                  child: Text('general.cancel'.tr()),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: _words.isEmpty ? null : _stop,
                  child: Text('general.done'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Rolling bar strip, newest sample on the right.
class _WavePainter extends CustomPainter {
  const _WavePainter({required this.levels, required this.color});

  final List<double> levels;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;
    final slot = size.width / levels.length;
    final barWidth = math.max(2.0, slot * 0.5);
    final mid = size.height / 2;
    // A floor, so silence reads as a quiet line rather than an empty box that
    // looks like the widget failed to render.
    const minHeight = 3.0;

    for (var i = 0; i < levels.length; i++) {
      final level = levels[i].clamp(0.0, 1.0);
      final h = minHeight + level * (size.height - minHeight);
      // Older samples fade, which gives the strip a direction and makes the
      // live end the one the eye goes to.
      final opacity = 0.25 + (i / levels.length) * 0.75;
      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;
      final x = slot * i + (slot - barWidth) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, mid - h / 2, barWidth, h),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => true;
}
