import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/auth/data/services/google_auth_service.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_event.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_state.dart';
import 'package:soplay/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:soplay/features/onboarding/presentation/onboarding_navigation.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _googlePending = false;

  /// Shown on the page until the next attempt clears it.
  String? _error;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _googlePending = false;
      _error = null;
    });
    context.read<AuthBloc>().add(
      AuthRegisterRequested(
        username: _usernameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
      ),
    );
  }

  void _signUpWithGoogle() {
    setState(() {
      _googlePending = true;
      _error = null;
    });
    context.read<AuthBloc>().add(const AuthGoogleRequested());
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/main');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (previous, current) =>
          current is AuthLoaded ||
          current is AuthError ||
          current is AuthInitial ||
          (current is AuthOtpPending && previous is! AuthOtpPending),
      listener: (context, state) {
        if (state is AuthLoaded) {
          // Prompts the password manager to keep what was just typed. Without
          // it Android never offers to save, and the next sign-in is manual
          // again.
          TextInput.finishAutofillContext();
          goAfterAuth(context);
        } else if (state is AuthOtpPending) {
          context.push('/otp', extra: state.email);
        } else if (state is AuthError) {
          setState(() {
            _googlePending = false;
            _error = state.message;
          });
        } else if (state is AuthInitial) {
          setState(() => _googlePending = false);
        }
      },
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          final loading = state is AuthLoading;
          return AuthScaffold(
            title: 'auth.create_account'.tr(),
            subtitle: 'auth.register_subtitle'.tr(),
            onClose: _close,
            children: [
              AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      AuthTextField(
                        controller: _usernameController,
                        hint: 'auth.username_hint'.tr(),
                        icon: Icons.person_outline_rounded,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.newUsername],
                        enabled: !loading,
                        validator: _validateUsername,
                      ),
                      const SizedBox(height: 12),
                      AuthTextField(
                        controller: _emailController,
                        hint: 'auth.email_hint'.tr(),
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        enabled: !loading,
                        validator: _validateEmail,
                      ),
                      const SizedBox(height: 12),
                      AuthTextField(
                        controller: _passwordController,
                        hint: 'auth.password_hint'.tr(),
                        icon: Icons.lock_outline_rounded,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.newPassword],
                        enabled: !loading,
                        suffix: IconButton(
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                            color: AppColors.textHint,
                          ),
                        ),
                        validator: _validatePassword,
                      ),
                      _PasswordStrength(password: _passwordController.text),
                      const SizedBox(height: 12),
                      AuthTextField(
                        controller: _confirmController,
                        hint: 'auth.confirm_password_hint'.tr(),
                        icon: Icons.lock_reset_rounded,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        enabled: !loading,
                        onFieldSubmitted: (_) => _submit(),
                        validator: _validateConfirm,
                      ),
                      const SizedBox(height: 20),
                      AuthErrorBanner(message: _error),
                      AuthPrimaryButton(
                        label: 'auth.sign_up'.tr(),
                        loading: loading && !_googlePending,
                        onPressed: loading ? null : _submit,
                      ),
                    ],
                  ),
                ),
              ),
              if (GoogleAuthService.isSupported) ...[
                const SizedBox(height: 22),
                const AuthDivider(),
                const SizedBox(height: 16),
                GoogleAuthButton(
                  loading: loading && _googlePending,
                  onPressed: loading ? null : _signUpWithGoogle,
                ),
              ],
              const SizedBox(height: 18),
              Text(
                'auth.terms_agree'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 6),
              AuthSwitchPrompt(
                text: 'auth.already_have_account'.tr(),
                action: 'auth.sign_in'.tr(),
                onTap: () => context.pushReplacement('/login'),
              ),
            ],
          );
        },
      ),
    );
  }

  String? _validateUsername(String? value) {
    final username = value?.trim() ?? '';
    if (username.isEmpty) return 'auth.username'.tr();
    if (username.length < 3) return 'auth.invalid_username'.tr();
    return null;
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'auth.email'.tr();
    if (!RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,}$').hasMatch(email)) {
      return 'auth.invalid_email'.tr();
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'auth.password'.tr();
    if (value.length < 6) return 'auth.invalid_password'.tr();
    return null;
  }

  /// Registration ends in an emailed code, so a mistyped password is only
  /// discovered minutes later at the login screen — cheap to catch here.
  String? _validateConfirm(String? value) {
    if (value != _passwordController.text) {
      return 'auth.passwords_not_match'.tr();
    }
    return null;
  }
}

class _PasswordStrength extends StatelessWidget {
  const _PasswordStrength({required this.password});

  final String password;

  int get _score {
    if (password.length < 6) return 0;
    var score = 1;
    if (password.length >= 10) score++;
    final varied = [
      RegExp(r'[a-z]'),
      RegExp(r'[A-Z]'),
      RegExp(r'[0-9]'),
      RegExp(r'[^A-Za-z0-9]'),
    ].where((r) => r.hasMatch(password)).length;
    if (varied >= 3) score++;
    return score.clamp(0, 3);
  }

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox(height: 12);

    const labels = ['auth.weak', 'auth.weak', 'auth.medium', 'auth.strong'];
    const colors = [
      AppColors.error,
      AppColors.error,
      AppColors.rating,
      AppColors.success,
    ];
    final score = _score;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                height: 3,
                decoration: BoxDecoration(
                  color: i < score ? colors[score] : AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
          const SizedBox(width: 10),
          Text(
            labels[score].tr(),
            style: TextStyle(color: colors[score], fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}
