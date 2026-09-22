import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_colors.dart';

class PinKeypad extends StatefulWidget {
  const PinKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.onBiometric,
    this.biometricIcon,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onBiometric;
  final IconData? biometricIcon;

  @override
  State<PinKeypad> createState() => _PinKeypadState();
}

class _PinKeypadState extends State<PinKeypad> {
  static final _numpad = <LogicalKeyboardKey, String>{
    LogicalKeyboardKey.numpad0: '0',
    LogicalKeyboardKey.numpad1: '1',
    LogicalKeyboardKey.numpad2: '2',
    LogicalKeyboardKey.numpad3: '3',
    LogicalKeyboardKey.numpad4: '4',
    LogicalKeyboardKey.numpad5: '5',
    LogicalKeyboardKey.numpad6: '6',
    LogicalKeyboardKey.numpad7: '7',
    LogicalKeyboardKey.numpad8: '8',
    LogicalKeyboardKey.numpad9: '9',
  };

  @override
  void initState() {
    super.initState();
    if (isDesktopPlatform) {
      HardwareKeyboard.instance.addHandler(_onKey);
    }
  }

  @override
  void dispose() {
    if (isDesktopPlatform) {
      HardwareKeyboard.instance.removeHandler(_onKey);
    }
    super.dispose();
  }

  // Desktop: accept physical keyboard input (digits + backspace) globally
  // while the keypad is on screen — independent of widget focus.
  bool _onKey(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete) {
      widget.onBackspace();
      return true;
    }
    final ch = event.character;
    if (ch != null && ch.length == 1 && '0123456789'.contains(ch)) {
      widget.onDigit(ch);
      return true;
    }
    final numpad = _numpad[key];
    if (numpad != null) {
      widget.onDigit(numpad);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final rows = <List<_Key>>[
      [_Key.digit('1'), _Key.digit('2'), _Key.digit('3')],
      [_Key.digit('4'), _Key.digit('5'), _Key.digit('6')],
      [_Key.digit('7'), _Key.digit('8'), _Key.digit('9')],
      [
        widget.onBiometric != null
            ? _Key.action(
                icon: widget.biometricIcon ?? Icons.fingerprint_rounded,
                action: _KeyAction.biometric,
              )
            : _Key.empty(),
        _Key.digit('0'),
        _Key.action(
          icon: Icons.backspace_outlined,
          action: _KeyAction.backspace,
        ),
      ],
    ];

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final k in row)
                  _KeyButton(data: k, onTap: () => _handle(k)),
              ],
            ),
          ),
      ],
    );

    // Desktop: keep the tiles grouped instead of spread across a wide window.
    // (Physical keyboard input is handled globally — see initState.)
    if (isDesktopPlatform) {
      return Center(child: SizedBox(width: 288, child: column));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: column,
    );
  }

  void _handle(_Key k) {
    HapticFeedback.selectionClick();
    switch (k.action) {
      case _KeyAction.digit:
        widget.onDigit(k.label!);
      case _KeyAction.backspace:
        widget.onBackspace();
      case _KeyAction.biometric:
        widget.onBiometric?.call();
      case _KeyAction.none:
        break;
    }
  }
}

enum _KeyAction { digit, backspace, biometric, none }

class _Key {
  _Key._({this.label, this.icon, required this.action});
  factory _Key.digit(String d) => _Key._(label: d, action: _KeyAction.digit);
  factory _Key.action({required IconData icon, required _KeyAction action}) =>
      _Key._(icon: icon, action: action);
  factory _Key.empty() => _Key._(action: _KeyAction.none);

  final String? label;
  final IconData? icon;
  final _KeyAction action;
}

class _KeyButton extends StatefulWidget {
  const _KeyButton({required this.data, required this.onTap});
  final _Key data;
  final VoidCallback onTap;

  @override
  State<_KeyButton> createState() => _KeyButtonState();
}

class _KeyButtonState extends State<_KeyButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (data.action == _KeyAction.none) {
      return const SizedBox(width: 72, height: 72);
    }

    final child = Center(
      child: data.icon != null
          ? Icon(data.icon, color: AppColors.textPrimary, size: 26)
          : Text(
              data.label!,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: isDesktopPlatform ? 24 : 28,
                fontWeight: isDesktopPlatform
                    ? FontWeight.w600
                    : FontWeight.w500,
              ),
            ),
    );

    // Sozo-Desktop: filled rounded-rect tiles with a hover lighten.
    if (isDesktopPlatform) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 78,
            height: 60,
            decoration: BoxDecoration(
              color: _hover ? AppColors.card : AppColors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: child,
          ),
        ),
      );
    }

    return SizedBox(
      width: 72,
      height: 72,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: widget.onTap, child: child),
      ),
    );
  }
}
