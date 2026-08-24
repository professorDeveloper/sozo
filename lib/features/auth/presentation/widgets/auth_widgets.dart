import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:soplay/core/widgets/app_buttons.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';
import 'package:soplay/features/onboarding/presentation/widgets/poster_wall.dart';

/// The shell every auth screen sits in: a living poster header that dissolves
/// into the page, then the form.
///
/// Shared rather than copied per page because the header is the only thing
/// tying sign-in, sign-up, the OTP step and the reset flow together — four
/// screens a person walks through in one sitting.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.children,
    required this.onClose,
    this.subtitle,
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final VoidCallback onClose;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final headerHeight = (MediaQuery.sizeOf(context).height * 0.34).clamp(
      200.0,
      320.0,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          children: [
            SizedBox(
              height: headerHeight,
              width: double.infinity,
              child: const PosterWall(columns: 6, tilesPerColumn: 9),
            ),
            // Darkens the posters enough for the brand row and the headline to
            // stay legible whatever poster happens to drift under them.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: headerHeight,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xCC000000),
                      Color(0x66000000),
                      Color(0x00000000),
                    ],
                    stops: [0, 0.45, 1],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AuthTopBar(onClose: onClose, onBack: onBack),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.only(
                        left: 20,
                        right: 20,
                        top: headerHeight * 0.42,
                        bottom: 28,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              subtitle!,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          ...children,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthTopBar extends StatelessWidget {
  const _AuthTopBar({required this.onClose, this.onBack});

  final VoidCallback onClose;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
              color: AppColors.textPrimary,
            )
          else
            const SizedBox(width: 12),
          Text(
            'app_name'.tr(),
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
            color: AppColors.textPrimary,
          ),
        ],
      ),
    );
  }
}

/// The input every auth screen uses.
///
/// Focus is drawn on the whole field — border, fill and the leading icon —
/// rather than a hairline underline. Over the poster header a borderless
/// filled box reads as decoration, not as somewhere to type.
class AuthTextField extends StatefulWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.suffix,
    this.onFieldSubmitted,
    this.autofillHints,
    this.inputFormatters,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final Widget? suffix;
  final ValueChanged<String>? onFieldSubmitted;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final bool enabled;
  final String? Function(String?)? validator;

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focused != _focusNode.hasFocus) {
        setState(() => _focused = _focusNode.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  OutlineInputBorder _border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color, width: width),
      );

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      focusNode: _focusNode,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      obscureText: widget.obscureText,
      enabled: widget.enabled,
      autofillHints: widget.autofillHints,
      inputFormatters: widget.inputFormatters,
      onFieldSubmitted: widget.onFieldSubmitted,
      cursorColor: AppColors.primary,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
      decoration: InputDecoration(
        hintText: widget.hint,
        filled: true,
        fillColor: _focused
            ? AppColors.surfaceVariant
            : AppColors.surface.withValues(alpha: 0.9),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 17,
        ),
        prefixIcon: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.only(left: 14, right: 10),
          child: Icon(
            widget.icon,
            size: 20,
            color: _focused ? AppColors.primary : AppColors.textHint,
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: widget.suffix,
        border: _border(AppColors.border),
        enabledBorder: _border(AppColors.border),
        disabledBorder: _border(AppColors.divider),
        focusedBorder: _border(AppColors.primary, 1.4),
        errorBorder: _border(AppColors.error, 1.2),
        focusedErrorBorder: _border(AppColors.error, 1.4),
        errorStyle: const TextStyle(color: AppColors.error, fontSize: 12),
      ),
      validator: widget.validator,
    );
  }
}

/// What went wrong, kept on the page.
///
/// A red snackbar covers the button the person is about to press again, and
/// leaves once they look away from it; this stays until the next attempt.
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: message == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.4),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 18,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          message!,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12.5,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// The one call-to-action on each screen, with the spinner built in so no page
/// re-invents the swap between label and progress.
/// The auth screens' name for [AppPrimaryButton].
///
/// Kept as a thin alias rather than deleted: its metrics became the app-wide
/// button in `app_theme.dart`, so there is now exactly one definition of what a
/// primary button is, and the dozen auth/onboarding call sites did not have to
/// be rewritten to say so.
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) => AppPrimaryButton(
    label: label,
    onPressed: onPressed,
    loading: loading,
  );
}

class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: AppColors.border, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'auth.or_continue_with'.tr(),
            style: const TextStyle(color: AppColors.textHint, fontSize: 12.5),
          ),
        ),
        Expanded(child: Divider(color: AppColors.border, height: 1)),
      ],
    );
  }
}

/// Google's own button, in Google's own colours — the branding guidelines are
/// not ours to restyle, and a red Sozo-coloured one reads as a phishing screen.
class GoogleAuthButton extends StatelessWidget {
  const GoogleAuthButton({
    super.key,
    required this.onPressed,
    this.loading = false,
  });

  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1F1F1F),
          disabledBackgroundColor: Colors.white24,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kButtonRadius),
          ),
        ),
        icon: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: Color(0xFF1F1F1F),
                  strokeWidth: 2.2,
                ),
              )
            : SvgPicture.asset(
                'assets/icons/google.svg',
                width: 20,
                height: 20,
              ),
        label: Text(
          'auth.continue_with_google'.tr(),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class AuthSwitchPrompt extends StatelessWidget {
  const AuthSwitchPrompt({
    super.key,
    required this.text,
    required this.action,
    required this.onTap,
  });

  final String text;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ),
        TextButton(
          onPressed: onTap,
          child: Text(
            action,
            style: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
