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

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  /// Which button is waiting. The bloc reports one AuthLoading for both paths,
  /// so without this the spinner lands on whichever button the page guesses.
  bool _googlePending = false;

  /// Shown on the page until the next attempt clears it.
  String? _error;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _googlePending = false;
      _error = null;
    });
    context.read<AuthBloc>().add(
      AuthLoginRequested(
        identifier: _identifierController.text.trim(),
        password: _passwordController.text,
      ),
    );
  }

  void _signInWithGoogle() {
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
      listener: (context, state) {
        if (state is AuthLoaded) {
          // Prompts the password manager to keep what was just typed. Without
          // it Android never offers to save, and the next sign-in is manual
          // again.
          TextInput.finishAutofillContext();
          context.go('/main');
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
            title: 'auth.welcome_back'.tr(),
            subtitle: 'auth.login_subtitle'.tr(),
            onClose: _close,
            children: [
              AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      AuthTextField(
                        controller: _identifierController,
                        hint: 'auth.identifier_hint'.tr(),
                        icon: Icons.person_outline_rounded,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        enabled: !loading,
                        validator: _validateIdentifier,
                      ),
                      const SizedBox(height: 12),
                      AuthTextField(
                        controller: _passwordController,
                        hint: 'auth.password_hint'.tr(),
                        icon: Icons.lock_outline_rounded,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        enabled: !loading,
                        onFieldSubmitted: (_) => _submit(),
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
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                          // Carries whatever was typed, so the reset page
                          // does not ask for an address the user just gave.
                          onPressed: () => context.push(
                            '/forgot-password',
                            extra: _identifierController.text.contains('@')
                                ? _identifierController.text.trim()
                                : null,
                          ),
                          child: Text(
                            'auth.forgot_password'.tr(),
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      AuthErrorBanner(message: _error),
                      AuthPrimaryButton(
                        label: 'auth.sign_in'.tr(),
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
                  onPressed: loading ? null : _signInWithGoogle,
                ),
              ],
              const SizedBox(height: 20),
              AuthSwitchPrompt(
                text: 'auth.dont_have_account'.tr(),
                action: 'auth.sign_up'.tr(),
                onTap: () => context.pushReplacement('/register'),
              ),
            ],
          );
        },
      ),
    );
  }

  String? _validateIdentifier(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'auth.identifier_required'.tr();
    if (v.contains('@')) {
      if (!RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,}$').hasMatch(v)) {
        return 'auth.invalid_email'.tr();
      }
    } else if (v.length < 3) {
      return 'auth.invalid_username'.tr();
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'auth.password'.tr();
    if (value.length < 6) return 'auth.invalid_password'.tr();
    return null;
  }
}
