import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/comments/domain/timed_reactions.dart';

typedef ReactionChoice = ({String kind, String value});

/// The quick bar: eight emoji and a short text option, over the bottom of the
/// video. Its own route, so typing never reaches the player's shortcuts and a
/// remote's BACK closes it.
Future<ReactionChoice?> showReactionPicker(BuildContext context) {
  return showGeneralDialog<ReactionChoice>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (context, _, _) => const _ReactionPicker(),
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: animation,
      child: child,
    ),
  );
}

class _ReactionPicker extends StatefulWidget {
  const _ReactionPicker();

  @override
  State<_ReactionPicker> createState() => _ReactionPickerState();
}

class _ReactionPickerState extends State<_ReactionPicker> {
  final TextEditingController _text = TextEditingController();
  bool _typing = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _sendText() {
    final value = _text.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop<ReactionChoice>((kind: 'text', value: value));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 96),
          child: Material(
            color: const Color(0xEE111111),
            borderRadius: BorderRadius.circular(28),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: _typing ? _buildTextRow() : _buildEmojiRow(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmojiRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < kTimedReactionEmoji.length; i++)
            _RoundButton(
              autofocus: i == 0,
              onTap: () => Navigator.of(context).pop<ReactionChoice>(
                (kind: 'emoji', value: kTimedReactionEmoji[i]),
              ),
              child: Text(
                kTimedReactionEmoji[i],
                style: const TextStyle(fontSize: 24),
              ),
            ),
          _RoundButton(
            tooltip: 'player.reaction_text'.tr(),
            onTap: () => setState(() => _typing = true),
            child: const Icon(
              Icons.short_text_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextRow() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 10),
          Flexible(
            child: TextField(
              controller: _text,
              autofocus: true,
              maxLength: kTimedReactionMaxText,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendText(),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'player.reaction_text_hint'.tr(),
                hintStyle: const TextStyle(color: Colors.white54),
                border: InputBorder.none,
                counterText: '',
                isCollapsed: true,
              ),
            ),
          ),
          _RoundButton(
            onTap: _sendText,
            child: Icon(Icons.send_rounded, color: AppColors.primary, size: 20),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.onTap,
    required this.child,
    this.autofocus = false,
    this.tooltip,
  });

  final VoidCallback onTap;
  final Widget child;
  final bool autofocus;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
      onTap: onTap,
      autofocus: autofocus,
      customBorder: const CircleBorder(),
      focusColor: Colors.white24,
      child: SizedBox(width: 44, height: 44, child: Center(child: child)),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
