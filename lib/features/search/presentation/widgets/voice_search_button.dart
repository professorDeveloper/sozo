import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/search/presentation/widgets/voice_search_dialog.dart';

/// Microphone button for the search field.
///
/// Renders nothing on the platforms with no recogniser to talk to, rather than
/// showing a button that reports a failure when pressed. On Android the
/// recogniser is also invisible without the `<queries>` entry in the manifest,
/// and the failure mode there is silent — the plugin simply says no recogniser
/// is available — so the check below covers both.
///
/// Partial results are reported as they arrive, so the field fills in while the
/// user is still speaking. That is what makes it feel like dictation rather
/// than a recording being uploaded, and it lets someone see a misheard word and
/// stop rather than waiting for a wrong search to run.
class VoiceSearchButton extends StatefulWidget {
  const VoiceSearchButton({
    super.key,
    required this.onText,
    this.onSubmit,
    this.size = 22,
  });

  /// Called for each result, partial ones included.
  final ValueChanged<String> onText;

  /// Called once with the final transcript, when the recogniser is done.
  final ValueChanged<String>? onSubmit;

  final double size;

  @override
  State<VoiceSearchButton> createState() => _VoiceSearchButtonState();
}

class _VoiceSearchButtonState extends State<VoiceSearchButton>
    with SingleTickerProviderStateMixin {
  final SpeechToText _speech = SpeechToText();

  bool _available = false;
  bool _listening = false;
  late final AnimationController _pulse;

  /// Only these have a system recogniser worth offering.
  static bool get _platformSupported => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (_platformSupported) _init();
  }

  Future<void> _init() async {
    try {
      final ok = await _speech.initialize(
        onStatus: (s) {
          if (!mounted) return;
          final listening = s == 'listening';
          if (listening != _listening) {
            setState(() => _listening = listening);
            listening ? _pulse.repeat(reverse: true) : _pulse.stop();
          }
        },
        onError: (_) {
          if (!mounted) return;
          setState(() => _listening = false);
          _pulse.stop();
        },
      );
      if (mounted) setState(() => _available = ok);
    } catch (_) {
      // A device with no recogniser, or one that refuses to initialise. The
      // button simply does not appear.
      if (mounted) setState(() => _available = false);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    // Not awaited: dispose cannot, and an orphaned recogniser session ends on
    // its own timeout anyway.
    _speech.cancel();
    super.dispose();
  }

  /// Open the listening dialog and run whatever it comes back with.
  ///
  /// The session itself lives in the dialog, which owns the waveform and needs
  /// the sound level anyway. This widget stays what it looks like: a button
  /// that knows whether the device can listen at all.
  Future<void> _open() async {
    if (_listening) return;
    final result = await VoiceSearchDialog.show(
      context,
      speech: _speech,
      onPartial: widget.onText,
    );
    final words = result?.trim() ?? '';
    if (words.isEmpty) return;
    widget.onText(words);
    widget.onSubmit?.call(words);
  }

  @override
  Widget build(BuildContext context) {
    if (!_platformSupported || !_available) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'search.voice'.tr(),
      onPressed: _open,
      icon: AnimatedBuilder(
        animation: _pulse,
        builder: (_, child) => Opacity(
          opacity: _listening ? 0.45 + (_pulse.value * 0.55) : 1,
          child: child,
        ),
        child: Icon(
          _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
          size: widget.size,
          color: _listening ? AppColors.primary : AppColors.textSecondary,
        ),
      ),
    );
  }
}
