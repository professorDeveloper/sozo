import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/tv/tv.dart';
import 'package:soplay/features/search/presentation/widgets/voice_search_dialog.dart';

/// Microphone button for the search field.
///
/// Shown on every platform with a system recogniser. Nothing is initialised
/// until it is pressed: the dialog does that, so the permission prompt comes
/// when the user asks to speak, and a refusal or a missing recogniser is
/// explained there instead of the button quietly disappearing.
///
/// Partial results are reported as they arrive, so the field fills in while
/// the user is still speaking.
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

  static bool get platformSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  State<VoiceSearchButton> createState() => VoiceSearchButtonState();
}

class VoiceSearchButtonState extends State<VoiceSearchButton> {
  final SpeechToText _speech = SpeechToText();
  bool _open = false;

  /// Opens the listening dialog. Also called by the TV remote's search key.
  Future<void> start() async {
    if (_open || !VoiceSearchButton.platformSupported) return;
    _open = true;
    try {
      final result = await VoiceSearchDialog.show(
        context,
        speech: _speech,
        onPartial: widget.onText,
      );
      final words = result?.trim() ?? '';
      if (words.isEmpty || !mounted) return;
      widget.onText(words);
      widget.onSubmit?.call(words);
    } finally {
      _open = false;
    }
  }

  @override
  void dispose() {
    // Not awaited: dispose cannot, and an orphaned session ends on its own.
    if (_speech.isListening) _speech.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!VoiceSearchButton.platformSupported) return const SizedBox.shrink();
    final icon = Icon(
      Icons.mic_none_rounded,
      size: widget.size,
      color: AppColors.textSecondary,
    );
    if (isTvPlatform) {
      return Tooltip(
        message: 'search.voice'.tr(),
        child: TvFocusable(
          onPressed: start,
          borderRadius: 9,
          child: icon,
        ),
      );
    }
    return IconButton(
      tooltip: 'search.voice'.tr(),
      onPressed: start,
      icon: icon,
    );
  }
}
