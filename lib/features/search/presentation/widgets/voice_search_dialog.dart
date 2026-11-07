import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'package:soplay/core/system/app_settings.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/search/presentation/widgets/voice_search_session.dart';

/// The listening dialog: a live waveform, the words as they are heard, and a
/// plain account of what went wrong when nothing usable came back.
///
/// The waveform is drawn from the recogniser's own sound level, not from a
/// timer, so it goes flat when the microphone stops hearing anything. The
/// level scale differs between Android and iOS, so a running peak normalises
/// whatever arrives.
///
/// The recogniser is initialised here, on the first tap, so the permission
/// prompt appears when the user asks to speak rather than when search opens.
///
/// Returns the final transcript, or null if the user backed out.
class VoiceSearchDialog extends StatefulWidget {
  const VoiceSearchDialog._({
    required this.speech,
    required this.onPartial,
    required this.appLocale,
  });

  final SpeechToText speech;

  /// Fires for every partial result so the field behind the dialog fills in
  /// alongside it.
  final ValueChanged<String> onPartial;

  final Locale appLocale;

  static Future<String?> show(
    BuildContext context, {
    required SpeechToText speech,
    required ValueChanged<String> onPartial,
  }) {
    final appLocale = context.locale;
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => VoiceSearchDialog._(
        speech: speech,
        onPartial: onPartial,
        appLocale: appLocale,
      ),
    );
  }

  @override
  State<VoiceSearchDialog> createState() => _VoiceSearchDialogState();
}

class _VoiceSearchDialogState extends State<VoiceSearchDialog>
    with SingleTickerProviderStateMixin {
  static const int _barCount = 34;

  /// A cold recogniser on a slow device genuinely takes a second or two.
  static const Duration _startDeadline = Duration(seconds: 6);

  /// Resolved once per app language; asking the recogniser is not free.
  static final Map<String, String?> _localeCache = {};

  final List<double> _levels = List<double>.filled(_barCount, 0);
  late final AnimationController _ticker;
  double _target = 0;
  double _peak = 1;

  VoiceSearchState _state = VoiceSearchState.initial;

  /// Bumped on every attempt so callbacks from an abandoned one are ignored.
  int _attempt = 0;

  /// Until the recogniser has started, `isListening` is false for an ordinary
  /// reason and must not be read as "it stopped".
  bool _everListened = false;

  String? _localeId;
  bool _localeDropped = false;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_advance);
    _begin();
  }

  void _set(VoiceSearchState next) {
    if (!mounted || next == _state) return;
    final wasActive = _state.isActive;
    setState(() => _state = next);
    if (next.phase == VoicePhase.done) {
      Navigator.of(context).pop(next.words);
      return;
    }
    if (wasActive && !next.isActive) {
      _ticker.stop();
      _levels.fillRange(0, _barCount, 0);
      widget.speech.cancel();
    }
  }

  Future<void> _begin() async {
    final attempt = ++_attempt;
    _everListened = false;
    _set(VoiceSearchMachine.retry());
    if (!_ticker.isAnimating) _ticker.repeat();

    final speech = widget.speech;
    var ok = false;
    try {
      ok = await speech.initialize();
    } catch (e) {
      debugPrint('[voice] initialize failed: $e');
    }
    if (!mounted || attempt != _attempt) return;
    if (!ok) {
      _set(VoiceSearchMachine.initFailed(hasPermission: await _hasPermission()));
      return;
    }
    // initialize() only takes listeners on its first successful call, and the
    // plugin is a singleton, so this dialog claims them directly.
    speech.errorListener = (e) => _onError(e, attempt);
    speech.statusListener = (s) {
      if (attempt == _attempt && s == SpeechToText.listeningStatus) {
        _everListened = true;
        _set(VoiceSearchMachine.listeningStarted(_state));
      }
    };

    if (!_localeDropped) _localeId = await _resolveLocale();
    if (!mounted || attempt != _attempt) return;
    await _listen(attempt);
  }

  Future<bool> _hasPermission() async {
    try {
      return await widget.speech.hasPermission;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _resolveLocale() async {
    final key = widget.appLocale.toLanguageTag();
    if (_localeCache.containsKey(key)) return _localeCache[key];
    String? id;
    try {
      final locales = await widget.speech.locales();
      final system = await widget.speech.systemLocale();
      id = matchSpeechLocale(
        widget.appLocale,
        locales.map((l) => l.localeId),
        systemLocaleId: system?.localeId,
      );
    } catch (e) {
      debugPrint('[voice] could not read recogniser locales: $e');
    }
    _localeCache[key] = id;
    return id;
  }

  Future<void> _listen(int attempt) async {
    try {
      if (widget.speech.isListening) await widget.speech.cancel();
      await widget.speech.listen(
        onResult: (r) {
          if (attempt != _attempt) return;
          final words = r.recognizedWords.trim();
          if (words.isNotEmpty) widget.onPartial(words);
          _set(VoiceSearchMachine.heard(_state, words, isFinal: r.finalResult));
        },
        onSoundLevelChange: (level) {
          final v = level.abs();
          if (v > _peak) _peak = v;
          _peak = math.max(1, _peak * 0.995);
          _target = (v / _peak).clamp(0.0, 1.0);
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenFor: const Duration(seconds: 20),
          pauseFor: const Duration(seconds: 3),
          localeId: _localeId,
        ),
      );
    } catch (e) {
      debugPrint('[voice] could not start listening: $e');
      if (!mounted || attempt != _attempt) return;
      _set(
        VoiceSearchMachine.listenFailed(hasPermission: await _hasPermission()),
      );
      return;
    }
    // listen() returns once the platform has been asked to start, not when the
    // session ends. A start that never happens is caught here; an end is
    // caught by the watchdog in [_advance].
    Future<void>.delayed(_startDeadline, () {
      if (mounted && attempt == _attempt && !_everListened) {
        _set(VoiceSearchMachine.startTimedOut(_state));
      }
    });
  }

  void _onError(SpeechRecognitionError e, int attempt) {
    if (!mounted || attempt != _attempt) return;
    debugPrint('[voice] ${e.errorMsg} permanent=${e.permanent}');
    // The app language is not one the recogniser can do after all: try once
    // more in the system language rather than failing outright.
    if (VoiceSearchMachine.isLanguageError(e.errorMsg) &&
        _localeId != null &&
        !_localeDropped) {
      _localeDropped = true;
      _localeCache[widget.appLocale.toLanguageTag()] = null;
      _begin();
      return;
    }
    _set(VoiceSearchMachine.error(_state, e.errorMsg, permanent: e.permanent));
  }

  void _advance() {
    if (!mounted || !_state.isActive) return;
    if (widget.speech.isListening) {
      _everListened = true;
      if (_state.phase == VoicePhase.starting) {
        _set(VoiceSearchMachine.listeningStarted(_state));
      }
    } else if (_everListened) {
      _set(VoiceSearchMachine.ended(_state));
      return;
    }
    for (var i = 0; i < _barCount - 1; i++) {
      _levels[i] = _levels[i + 1];
    }
    final last = _levels[_barCount - 1];
    _levels[_barCount - 1] = last + (_target - last) * 0.35;
    _target *= 0.92;
    setState(() {});
  }

  Future<void> _stop() async {
    // stop() asks for a final result; cancel() would throw away the words
    // already on screen, which is not what a Done button means.
    await widget.speech.stop();
    if (!mounted) return;
    _set(VoiceSearchMachine.ended(_state));
  }

  void _cancel() {
    _attempt++;
    widget.speech.cancel();
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _attempt++;
    _ticker.dispose();
    widget.speech.errorListener = null;
    widget.speech.statusListener = null;
    if (widget.speech.isListening) widget.speech.cancel();
    super.dispose();
  }

  (IconData, String, String?) get _copy {
    switch (_state.phase) {
      case VoicePhase.starting:
        return (Icons.mic_none_rounded, 'search.voice_starting'.tr(), null);
      case VoicePhase.listening:
      case VoicePhase.done:
        return (Icons.mic_rounded, 'search.voice_listening'.tr(), null);
      case VoicePhase.noSpeech:
        return (
          Icons.hearing_disabled_rounded,
          'search.voice_no_speech'.tr(),
          'search.voice_no_speech_hint'.tr(),
        );
      case VoicePhase.permissionDenied:
        return (
          Icons.mic_off_rounded,
          'search.voice_permission'.tr(),
          'search.voice_permission_hint'.tr(),
        );
      case VoicePhase.unavailable:
        return (
          Icons.mic_off_rounded,
          'search.voice_unavailable'.tr(),
          'search.voice_unavailable_hint'.tr(),
        );
      case VoicePhase.network:
        return (
          Icons.wifi_off_rounded,
          'search.voice_network'.tr(),
          'search.voice_network_hint'.tr(),
        );
      case VoicePhase.recognizer:
        return (
          Icons.error_outline_rounded,
          'search.voice_error'.tr(),
          'search.voice_error_hint'.tr(),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, title, hint) = _copy;
    final active = _state.isActive;
    final words = _state.words;
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 30,
                color: _state.phase == VoicePhase.listening
                    ? AppColors.primary
                    : AppColors.textHint,
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 18),
              if (active) ...[
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
              ],
              // Reserves its own height so the dialog does not jump the
              // moment the first word arrives.
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Center(
                  child: Text(
                    active
                        ? (words.isEmpty ? 'search.voice_hint'.tr() : words)
                        : (hint ?? ''),
                    textAlign: TextAlign.center,
                    maxLines: active ? 2 : 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: active && words.isNotEmpty ? 16 : 13,
                      fontWeight: active && words.isNotEmpty
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: active && words.isNotEmpty
                          ? AppColors.textPrimary
                          : AppColors.textHint,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                children: [
                  TextButton(
                    // While listening there is nothing else to focus: Done
                    // stays disabled until a word is heard.
                    autofocus: isTvPlatform && active,
                    onPressed: _cancel,
                    child: Text('general.cancel'.tr()),
                  ),
                  if (active)
                    TextButton(
                      onPressed: words.isEmpty ? null : _stop,
                      child: Text('general.done'.tr()),
                    ),
                  if (_state.phase == VoicePhase.permissionDenied)
                    TextButton(
                      onPressed: openAppSettings,
                      child: Text('search.voice_open_settings'.tr()),
                    ),
                  if (_state.canRetry)
                    TextButton(
                      // A remote has no other way into the dialog's buttons.
                      autofocus: isTvPlatform,
                      onPressed: _begin,
                      child: Text('search.voice_try_again'.tr()),
                    ),
                ],
              ),
            ],
          ),
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
    // A floor, so silence reads as a quiet line rather than an empty box.
    const minHeight = 3.0;

    for (var i = 0; i < levels.length; i++) {
      final level = levels[i].clamp(0.0, 1.0);
      final h = minHeight + level * (size.height - minHeight);
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
