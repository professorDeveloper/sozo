import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/app_lock/presentation/widgets/pin_dots.dart';
import 'package:soplay/features/app_lock/presentation/widgets/pin_keypad.dart';

/// A profile PIN is four digits, checked as soon as the last one is entered.
class ProfilePinPage extends StatefulWidget {
  const ProfilePinPage._({
    required this.creating,
    required this.title,
    required this.subtitle,
    this.header,
    this.onSubmit,
  });

  static const int length = 4;

  final bool creating;
  final String title;
  final String subtitle;
  final Widget? header;

  /// Checks a PIN; returns an error message, or null when it was accepted.
  final Future<String?> Function(String pin)? onSubmit;

  /// Returns the accepted PIN, or null if the page was closed.
  static Future<String?> verify(
    BuildContext context, {
    required String title,
    required String subtitle,
    Widget? header,
    required Future<String?> Function(String pin) onSubmit,
  }) => Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ProfilePinPage._(
        creating: false,
        title: title,
        subtitle: subtitle,
        header: header,
        onSubmit: onSubmit,
      ),
    ),
  );

  /// Asks for a new PIN twice; returns it, or null if the page was closed.
  static Future<String?> create(BuildContext context, {Widget? header}) =>
      Navigator.of(context).push<String>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ProfilePinPage._(
            creating: true,
            title: 'profiles.pin_create_title'.tr(),
            subtitle: 'profiles.pin_create_subtitle'.tr(),
            header: header,
          ),
        ),
      );

  @override
  State<ProfilePinPage> createState() => _ProfilePinPageState();
}

class _ProfilePinPageState extends State<ProfilePinPage> {
  String _entered = '';
  String? _first;
  String? _error;
  int _errorTick = 0;
  bool _busy = false;

  bool get _confirming => widget.creating && _first != null;

  void _digit(String d) {
    if (_busy || _entered.length >= ProfilePinPage.length) return;
    setState(() {
      _entered += d;
      _error = null;
    });
    if (_entered.length == ProfilePinPage.length) {
      // A beat so the last dot is seen filling before the page reacts.
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (mounted && _entered.length == ProfilePinPage.length) _continue();
      });
    }
  }

  void _backspace() {
    if (_busy || _entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  void _fail(String message) {
    setState(() {
      _error = message;
      _errorTick++;
      _entered = '';
    });
  }

  Future<void> _continue() async {
    final pin = _entered;
    if (pin.length != ProfilePinPage.length || _busy) return;
    if (widget.creating) {
      if (_first == null) {
        setState(() {
          _first = pin;
          _entered = '';
        });
        return;
      }
      if (_first != pin) {
        _first = null;
        _fail('profiles.pin_mismatch'.tr());
        return;
      }
      Navigator.of(context).pop(pin);
      return;
    }
    setState(() => _busy = true);
    final error = await widget.onSubmit!(pin);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error == null) {
      Navigator.of(context).pop(pin);
    } else {
      _fail(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _confirming
        ? 'profiles.pin_confirm_title'.tr()
        : widget.title;
    final subtitle = _confirming
        ? 'profiles.pin_confirm_subtitle'.tr()
        : widget.subtitle;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    ?widget.header,
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    PinDots(
                      length: ProfilePinPage.length,
                      filled: _entered.length,
                      errorTick: _errorTick,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 36,
                      child: _busy
                          ? const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : _error == null
                          ? null
                          : Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              child: Text(
                                _error!,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                style: const TextStyle(
                                  color: AppColors.error,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                    ),
                    const Spacer(),
                    PinKeypad(onDigit: _digit, onBackspace: _backspace),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
